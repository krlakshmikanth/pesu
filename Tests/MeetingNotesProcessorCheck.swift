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
        precondition(legacy.decisions.count == 2)
        precondition(legacy.decisions[0].evidenceSegmentID == "segment-1")
        precondition(legacy.decisions[1].evidenceSegmentID == "segment-2")

        let genericBrief = MeetingNotesProcessor.process(
            rawResponse: """
            Brief: The meeting discussed various topics and participants talked about several things.
            Decisions:
            S1: Discussed the release plan.
            S2: Talked about the timeline.
            """,
            transcript: transcript
        )
        precondition(!genericBrief.brief.lowercased().contains("various topics"))
        precondition(genericBrief.decisions.isEmpty || genericBrief.decisions.allSatisfy {
            !$0.text.lowercased().contains("discussed the")
        })

        let weakEvidence = MeetingNotesProcessor.process(
            rawResponse: """
            Brief: Maya and You agreed to ship the private alpha on Friday and prepare release notes tomorrow.
            Decisions:
            S1: Approve the quarterly budget increase.
            S2: Ship the private alpha on Friday.
            """,
            transcript: transcript
        )
        precondition(weakEvidence.decisions.count == 1)
        precondition(weakEvidence.decisions[0].text == "Ship the private alpha on Friday.")
        precondition(weakEvidence.decisions[0].evidenceSegmentID == "segment-1")

        let transcriptOnly = MeetingNotesProcessor.processFromTranscript([
            TranscriptSegment(id: "s1", timestamp: "00:05", speaker: "Alex", text: "Okay."),
            TranscriptSegment(id: "s2", timestamp: "00:18", speaker: "Alex", text: "We will move the launch to March."),
            TranscriptSegment(id: "s3", timestamp: "00:30", speaker: "You", text: "Sounds good.")
        ])
        precondition(transcriptOnly.decisions.count == 1)
        precondition(transcriptOnly.decisions[0].text == "We will move the launch to March.")
        precondition(transcriptOnly.decisions[0].evidenceSegmentID == "s2")

        let refined = MeetingNotesProcessor.refineStoredDecisions([
            Decision(id: "01", text: "Discussed the roadmap in general terms.", evidenceSegmentID: "segment-1"),
            Decision(id: "02", text: "Ship the private alpha on Friday.", evidenceSegmentID: "segment-1")
        ], transcript: transcript)
        precondition(refined.count == 1)
        precondition(refined[0].text == "Ship the private alpha on Friday.")

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
