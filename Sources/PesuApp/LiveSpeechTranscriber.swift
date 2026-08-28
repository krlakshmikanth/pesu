import AVFoundation
import CoreMedia
import Foundation
import Speech

@available(macOS 26.0, *)
actor LiveSpeechTranscriber {
    enum TranscriptionError: LocalizedError {
        case localeUnsupported
        case modelUnavailable
        case audioFormatUnavailable
        case audioConversionFailed

        var errorDescription: String? {
            switch self {
            case .localeUnsupported: "Apple Speech does not support the current language."
            case .modelUnavailable: "The Apple Speech model could not be prepared on this Mac."
            case .audioFormatUnavailable: "Apple Speech could not choose a compatible audio format."
            case .audioConversionFailed: "Microphone audio could not be converted for live transcription."
            }
        }
    }

    private let sink = AnalyzerInputSink()
    private let speaker: String
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var resultTask: Task<Void, Never>?
    private var finalizedSegments: [TranscriptSegment] = []
    private var volatileText = ""
    private var onUpdate: (@Sendable (LiveTranscriptSnapshot) -> Void)?

    init(speaker: String) {
        self.speaker = speaker
    }

    nonisolated func append(_ buffer: AVAudioPCMBuffer) {
        sink.append(buffer)
    }

    func start(
        locale requestedLocale: Locale = .current,
        onUpdate: @escaping @Sendable (LiveTranscriptSnapshot) -> Void
    ) async throws {
        await cancel()
        self.onUpdate = onUpdate
        publish(status: "Preparing on-device Apple Speech…")

        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw TranscriptionError.localeUnsupported
        }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange]
        )
        try await ensureModel(for: transcriber)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.audioFormatUnavailable
        }
        try await analyzer.prepareToAnalyze(in: analyzerFormat)

        let input = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .unbounded)
        sink.configure(continuation: input.continuation, analyzerFormat: analyzerFormat)
        self.transcriber = transcriber
        self.analyzer = analyzer
        finalizedSegments = []
        volatileText = ""

        resultTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    await self?.handle(result)
                }
            } catch {
                await self?.publish(status: "Live transcription stopped: \(error.localizedDescription)")
            }
        }
        try await analyzer.start(inputSequence: input.stream)
        publish(status: "Live transcription · on device")
    }

    func stop() async -> [TranscriptSegment] {
        sink.finish()
        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        await resultTask?.value
        resultTask = nil
        analyzer = nil
        transcriber = nil
        volatileText = ""
        publish(status: finalizedSegments.isEmpty ? "No speech detected" : "Transcript finalized locally")
        return finalizedSegments
    }

    func cancel() async {
        sink.finish()
        if let analyzer { await analyzer.cancelAndFinishNow() }
        resultTask?.cancel()
        resultTask = nil
        analyzer = nil
        transcriber = nil
        finalizedSegments = []
        volatileText = ""
    }

    private func ensureModel(for transcriber: SpeechTranscriber) async throws {
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            return
        case .supported, .downloading:
            publish(status: "Downloading the Apple Speech model…")
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await installation.downloadAndInstall()
            }
            guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
                throw TranscriptionError.modelUnavailable
            }
        case .unsupported:
            throw TranscriptionError.modelUnavailable
        @unknown default:
            throw TranscriptionError.modelUnavailable
        }
    }

    private func handle(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if result.isFinal {
            volatileText = ""
            let seconds = max(0, CMTimeGetSeconds(result.range.start))
            let segment = TranscriptSegment(
                id: UUID().uuidString,
                timestamp: Self.timestamp(seconds),
                speaker: speaker,
                text: text
            )
            if finalizedSegments.last?.text != text || finalizedSegments.last?.timestamp != segment.timestamp {
                finalizedSegments.append(segment)
            }
        } else {
            volatileText = text
        }
        publish(status: "Live transcription · on device")
    }

    private func publish(status: String) {
        onUpdate?(LiveTranscriptSnapshot(
            finalizedSegments: finalizedSegments,
            volatileText: volatileText,
            status: status
        ))
    }

    private static func timestamp(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "00:00" }
        let whole = max(0, Int(seconds))
        return String(format: "%02d:%02d", whole / 60, whole % 60)
    }
}

@available(macOS 26.0, *)
private final class AnalyzerInputSink: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var converterSourceFormat: AVAudioFormat?

    func configure(
        continuation: AsyncStream<AnalyzerInput>.Continuation,
        analyzerFormat: AVAudioFormat
    ) {
        lock.lock()
        self.continuation = continuation
        self.analyzerFormat = analyzerFormat
        converter = nil
        converterSourceFormat = nil
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation, let analyzerFormat else { return }

        if buffer.format == analyzerFormat {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }

        if converter == nil || converterSourceFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: analyzerFormat)
            converterSourceFormat = buffer.format
        }
        guard let converter else { return }

        let ratio = analyzerFormat.sampleRate / max(buffer.format.sampleRate, 1)
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }

        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, outputStatus in
            if supplied {
                outputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, conversionError == nil else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    func finish() {
        lock.lock()
        continuation?.finish()
        continuation = nil
        analyzerFormat = nil
        converter = nil
        converterSourceFormat = nil
        lock.unlock()
    }
}
