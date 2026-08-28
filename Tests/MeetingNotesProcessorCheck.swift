import Foundation

@main
enum MeetingNotesProcessorCheck {
    static func main() {
        let transcript = [
            TranscriptSegment(id: "segment-1", timestamp: "00:12", speaker: "Maya", text: "We will ship the private alpha on Friday."),
            TranscriptSegment(id: "segment-2", timestamp: "00:24", speaker: "You", text: "I will prepare the release notes tomorrow.")
        ]
        let raw = """
        **Summary**: “The team agreed to ship a private alpha on Friday.”

        **Decisions**:
        - S1: Ship the private alpha on Friday.

        **Actions**:
        - Prepare the release notes tomorrow. ✅
        """
        let notes = MeetingNotesProcessor.process(rawResponse: raw, transcript: transcript)
        precondition(notes.brief == "The team agreed to ship a private alpha on Friday.")
        precondition(notes.decisions.count == 1)
        precondition(notes.decisions[0].text == "Ship the private alpha on Friday.")
        precondition(notes.decisions[0].evidenceSegmentID == "segment-1")
        precondition(!notes.brief.contains("**"))
        precondition(!notes.brief.contains("“"))
        precondition(MeetingNotesProcessor.cleanDisplayText("✅ **Done**") == "Done")

        let legacy = MeetingNotesProcessor.process(
            rawResponse: "Live transcript captured locally using K66.",
            transcript: transcript
        )
        precondition(legacy.brief == "We will ship the private alpha on Friday. I will prepare the release notes tomorrow.")

        let meeting = Meeting(
            id: 1,
            title: "Private alpha review",
            startedAt: Date(timeIntervalSince1970: 1_787_840_000),
            duration: 1_800,
            participants: ["Maya"],
            summary: notes.brief,
            decisions: notes.decisions,
            transcript: transcript,
            systemAudioPath: nil,
            microphonePath: nil
        )
        let markdown = MeetingMarkdownExporter.markdown(for: meeting)
        precondition(markdown.contains("# Private alpha review"))
        precondition(markdown.contains("Evidence: 00:12, Maya."))
        precondition(markdown.contains("## Transcript"))
        precondition(MeetingMarkdownExporter.fileName(for: meeting) == "Private-alpha-review.md")
        print("Meeting note cleanup, evidence, and Markdown export checks passed")
    }
}
