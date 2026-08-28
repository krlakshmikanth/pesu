import Foundation

@main
enum LiveTranscriptMergeCheck {
    static func main() {
        let microphone = LiveTranscriptSnapshot(
            finalizedSegments: [segment("00:05", "You", "Can everyone see the plan?")],
            volatileText: "Let us start",
            status: "Live transcription · on device"
        )
        let system = LiveTranscriptSnapshot(
            finalizedSegments: [
                segment("00:02", "Meeting", "Yes, it is visible."),
                segment("01:10", "Meeting", "The next milestone is Friday.")
            ],
            volatileText: "We also need",
            status: "Live transcription · on device"
        )

        let merged = LiveTranscriptMerge.combine(microphone: microphone, system: system)
        precondition(merged.finalizedSegments.map(\.timestamp) == ["00:02", "00:05", "01:10"])
        precondition(merged.finalizedSegments.map(\.speaker) == ["Meeting", "You", "Meeting"])
        precondition(merged.volatileText == "You: Let us start\nMeeting: We also need")
        precondition(merged.status == "Live transcription · system + mic · on device")

        let preparing = LiveTranscriptMerge.combine(
            microphone: LiveTranscriptMerge.empty,
            system: LiveTranscriptSnapshot(finalizedSegments: [], volatileText: "", status: "Downloading the Apple Speech model…")
        )
        precondition(preparing.status == "Downloading the Apple Speech model…")

        print("Live transcript merge checks passed")
    }

    private static func segment(_ time: String, _ speaker: String, _ text: String) -> TranscriptSegment {
        TranscriptSegment(id: UUID().uuidString, timestamp: time, speaker: speaker, text: text)
    }
}
