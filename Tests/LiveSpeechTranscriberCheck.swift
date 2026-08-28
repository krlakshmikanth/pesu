import AVFoundation
import Foundation

@available(macOS 26.0, *)
@main
enum LiveSpeechTranscriberCheck {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Pass a local speech audio file")
        }

        let audioFile = try AVAudioFile(forReading: URL(fileURLWithPath: CommandLine.arguments[1]))
        let transcriber = LiveSpeechTranscriber(speaker: "Test")
        try await transcriber.start(locale: Locale(identifier: "en_GB")) { _ in }

        while audioFile.framePosition < audioFile.length {
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: 4_096
            ) else { fatalError("Could not allocate an audio buffer") }
            try audioFile.read(into: buffer)
            if buffer.frameLength == 0 { break }
            transcriber.append(buffer)
        }

        let segments = await transcriber.stop()
        precondition(!segments.isEmpty, "Apple Speech returned no finalized transcription")
        precondition(segments.allSatisfy { $0.speaker == "Test" })
        print("Apple Speech finalized: \(segments.map(\.text).joined(separator: " "))")
    }
}
