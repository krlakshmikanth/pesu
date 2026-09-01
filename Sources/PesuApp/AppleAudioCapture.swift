import AVFoundation
import Foundation

struct CaptureFiles: Sendable {
    let systemAudioURL: URL
    let microphoneURL: URL
}

final class AppleAudioCapture: @unchecked Sendable {
    enum CaptureError: LocalizedError {
        case unavailable
        case microphoneDenied

        var errorDescription: String? {
            switch self {
            case .unavailable: "Apple audio capture is unavailable."
            case .microphoneDenied: "Microphone access is required for recording and live transcription."
            }
        }
    }

    private enum TranscriptSource {
        case microphone
        case system
    }

    private let systemCapture = CoreAudioTapCapture()
    private let microphoneCapture = MicrophoneCapture()
    private let microphoneTranscriber = LiveSpeechTranscriber(speaker: "You")
    private let systemTranscriber = LiveSpeechTranscriber(speaker: "Meeting")
    private let transcriptLock = NSLock()
    private var microphoneSnapshot = LiveTranscriptMerge.empty
    private var systemSnapshot = LiveTranscriptMerge.empty
    private var transcriptUpdate: (@Sendable (LiveTranscriptSnapshot) -> Void)?
    private var isCapturing = false
    private(set) var files: CaptureFiles?

    static func availableMicrophones() -> [MicrophoneOption] {
        let defaultDevice = AVCaptureDevice.default(for: .audio)
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        var seen: Set<String> = []
        let devices = discovery.devices
            .filter { seen.insert($0.uniqueID).inserted }
            .sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }
            .map { device in
                MicrophoneOption(
                    id: device.uniqueID,
                    name: device.localizedName,
                    detail: device.uniqueID == defaultDevice?.uniqueID ? "Current system microphone" : "Available microphone",
                    captureDeviceID: device.uniqueID
                )
            }
        return [
            MicrophoneOption(
                id: MicrophoneOption.systemDefaultID,
                name: "System Default",
                detail: defaultDevice.map { "Currently \($0.localizedName)" } ?? "Follows macOS input settings",
                captureDeviceID: nil
            )
        ] + devices
    }

    func start(
        microphoneDeviceID: String?,
        onTranscriptUpdate: @escaping @Sendable (LiveTranscriptSnapshot) -> Void
    ) async throws -> CaptureFiles {
        guard !isCapturing else {
            if let files { return files }
            throw CaptureError.unavailable
        }
        isCapturing = true

        let microphoneAllowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneAllowed = true
        case .notDetermined:
            microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            microphoneAllowed = false
        }
        guard microphoneAllowed else {
            isCapturing = false
            throw CaptureError.microphoneDenied
        }

        transcriptLock.withLock {
            transcriptUpdate = onTranscriptUpdate
            microphoneSnapshot = LiveTranscriptMerge.empty
            systemSnapshot = LiveTranscriptMerge.empty
        }

        do {
            try await microphoneTranscriber.start { [weak self] snapshot in
                self?.receive(snapshot, from: .microphone)
            }
            try await systemTranscriber.start { [weak self] snapshot in
                self?.receive(snapshot, from: .system)
            }

            let recordings = PesuStorage.recordingsDirectory
            try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let files = CaptureFiles(
                systemAudioURL: recordings.appendingPathComponent("\(stamp)-system.m4a"),
                microphoneURL: recordings.appendingPathComponent("\(stamp)-microphone.m4a")
            )
            self.files = files

            try systemCapture.start(url: files.systemAudioURL) { [systemTranscriber] buffer in
                systemTranscriber.append(buffer)
            }
            try microphoneCapture.start(deviceID: microphoneDeviceID, url: files.microphoneURL) { [microphoneTranscriber] buffer in
                microphoneTranscriber.append(buffer)
            }
            return files
        } catch {
            systemCapture.stop()
            microphoneCapture.stop()
            await microphoneTranscriber.cancel()
            await systemTranscriber.cancel()
            transcriptLock.withLock { transcriptUpdate = nil }
            files = nil
            isCapturing = false
            throw error
        }
    }

    func stop() async -> [TranscriptSegment] {
        systemCapture.stop()
        microphoneCapture.stop()

        async let microphoneTranscript = microphoneTranscriber.stop()
        async let systemTranscript = systemTranscriber.stop()
        let transcript = await (microphoneTranscript + systemTranscript).sorted {
            let left = $0.timestamp.split(separator: ":").compactMap { Int($0) }
            let right = $1.timestamp.split(separator: ":").compactMap { Int($0) }
            return (left.first ?? .max, left.last ?? .max) < (right.first ?? .max, right.last ?? .max)
        }
        transcriptLock.withLock { transcriptUpdate = nil }
        files = nil
        isCapturing = false
        return transcript
    }

    private func receive(_ snapshot: LiveTranscriptSnapshot, from source: TranscriptSource) {
        let delivery: ((@Sendable (LiveTranscriptSnapshot) -> Void), LiveTranscriptSnapshot)? = transcriptLock.withLock {
            switch source {
            case .microphone: microphoneSnapshot = snapshot
            case .system: systemSnapshot = snapshot
            }
            guard let transcriptUpdate else { return nil }
            return (transcriptUpdate, LiveTranscriptMerge.combine(
                microphone: microphoneSnapshot,
                system: systemSnapshot
            ))
        }
        if let (update, combined) = delivery { update(combined) }
    }
}
