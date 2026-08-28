import Foundation

enum LiveTranscriptMerge {
    static let empty = LiveTranscriptSnapshot(
        finalizedSegments: [],
        volatileText: "",
        status: "Preparing on-device Apple Speech…"
    )

    static func combine(
        microphone: LiveTranscriptSnapshot,
        system: LiveTranscriptSnapshot
    ) -> LiveTranscriptSnapshot {
        let finalized = (microphone.finalizedSegments + system.finalizedSegments).sorted {
            let left = seconds(from: $0.timestamp)
            let right = seconds(from: $1.timestamp)
            if left == right { return $0.speaker.localizedCaseInsensitiveCompare($1.speaker) == .orderedDescending }
            return left < right
        }

        let volatile = [
            labeled(microphone.volatileText, speaker: "You"),
            labeled(system.volatileText, speaker: "Meeting")
        ]
            .compactMap { $0 }
            .joined(separator: "\n")

        return LiveTranscriptSnapshot(
            finalizedSegments: finalized,
            volatileText: volatile,
            status: combinedStatus(microphone.status, system.status)
        )
    }

    private static func labeled(_ text: String, speaker: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "\(speaker): \(trimmed)"
    }

    private static func combinedStatus(_ microphone: String, _ system: String) -> String {
        let statuses = [microphone, system]
        if let failure = statuses.first(where: { $0.contains("stopped:") }) { return failure }
        if statuses.contains(where: { $0.contains("Downloading") }) { return "Downloading the Apple Speech model…" }
        if statuses.contains(where: { $0.contains("Preparing") }) { return "Preparing on-device Apple Speech…" }
        if statuses.allSatisfy({ $0 == "No speech detected" }) { return "No speech detected" }
        if statuses.allSatisfy({ $0 == "Transcript finalized locally" || $0 == "No speech detected" }) {
            return "Transcript finalized locally"
        }
        return "Live transcription · system + mic · on device"
    }

    private static func seconds(from timestamp: String) -> Int {
        let parts = timestamp.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return .max }
        return parts[0] * 60 + parts[1]
    }
}
