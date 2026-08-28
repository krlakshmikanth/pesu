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
        precondition(!notes.brief.contains("**"))
        precondition(!notes.brief.contains("“"))
        precondition(MeetingNotesProcessor.cleanDisplayText("✅ **Done**") == "Done")

        let legacy = MeetingNotesProcessor.process(
            rawResponse: "Live transcript captured locally using K66.",
            transcript: transcript
        )
        precondition(!legacy.brief.contains("We will ship the private alpha on Friday."))
        precondition(!legacy.brief.contains("I will prepare the release notes tomorrow."))
        precondition(legacy.brief.lowercased().contains("private alpha") || legacy.brief.lowercased().contains("release notes"))
        precondition(legacy.decisions.count == 2)
        precondition(legacy.decisions.contains { $0.text.lowercased().contains("ship the private alpha") })
        precondition(legacy.decisions.contains { $0.text.lowercased().contains("release notes") })

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

        let transcriptOnly = MeetingNotesProcessor.processFromTranscript([
            TranscriptSegment(id: "s1", timestamp: "00:05", speaker: "Alex", text: "Okay."),
            TranscriptSegment(id: "s2", timestamp: "00:18", speaker: "Alex", text: "We will move the launch to March."),
            TranscriptSegment(id: "s3", timestamp: "00:30", speaker: "You", text: "Sounds good.")
        ])
        precondition(transcriptOnly.decisions.count == 1)
        precondition(transcriptOnly.decisions[0].text == "Move the launch to March.")
        precondition(transcriptOnly.brief.lowercased().contains("launch") || transcriptOnly.brief.lowercased().contains("march"))
        precondition(!transcriptOnly.brief.hasPrefix("We will move the launch to March."))

        let refined = MeetingNotesProcessor.refineStoredDecisions([
            Decision(id: "01", text: "Discussed the roadmap in general terms.", evidenceSegmentID: "segment-1"),
            Decision(id: "02", text: "Ship the private alpha on Friday.", evidenceSegmentID: "segment-1")
        ], transcript: transcript)
        precondition(refined.count == 1)
        precondition(refined[0].text == "Ship the private alpha on Friday.")

        var manySegments: [TranscriptSegment] = (1...12).map { index in
            TranscriptSegment(
                id: "item-\(index)",
                timestamp: String(format: "00:%02d", index),
                speaker: "Alex",
                text: "I will check the docs for item \(index)."
            )
        }
        manySegments.append(
            TranscriptSegment(id: "ship", timestamp: "01:00", speaker: "Maya", text: "We decided to ship the alpha on Friday.")
        )
        let capped = MeetingNotesProcessor.processFromTranscript(manySegments)
        precondition(capped.decisions.count <= 8)
        precondition(capped.decisions.contains { $0.text.lowercased().contains("ship the alpha") })

        let connectd = MeetingNotesProcessor.processFromTranscript([
            TranscriptSegment(id: "c1", timestamp: "00:39", speaker: "Meeting", text: "Yeah, yeah, you know, um, we are here to talk about the advisors for Lat Health."),
            TranscriptSegment(id: "c2", timestamp: "02:06", speaker: "Meeting", text: "Um, okay, let's do the advisors first."),
            TranscriptSegment(id: "c3", timestamp: "02:10", speaker: "Meeting", text: "Let's get through that 1st."),
            TranscriptSegment(id: "c4", timestamp: "02:28", speaker: "Meeting", text: "So the 1st advisor that we're going to go through was that fundraising advisor."),
            TranscriptSegment(id: "c5", timestamp: "02:55", speaker: "Meeting", text: "So the 1st person I want to bring up is Vishal."),
            TranscriptSegment(id: "c6", timestamp: "05:36", speaker: "You", text: "We are very early stage. I would say like, maybe skip this for now."),
            TranscriptSegment(id: "c7", timestamp: "08:35", speaker: "Meeting", text: "This is Adrian, so I look at Adrian."),
            TranscriptSegment(id: "c8", timestamp: "10:06", speaker: "Meeting", text: "So yeah, we can go ahead with this."),
            TranscriptSegment(id: "c9", timestamp: "13:15", speaker: "Meeting", text: "Okay, so the next is that clinical health advisor."),
            TranscriptSegment(id: "c10", timestamp: "17:49", speaker: "You", text: "I mean her profile looks more relevant to what we are looking for, considering the previous profile."),
            TranscriptSegment(id: "c11", timestamp: "19:04", speaker: "Meeting", text: "Jackson Cole. have a look and let me know what your thoughts are."),
            TranscriptSegment(id: "c12", timestamp: "19:23", speaker: "You", text: "Ah, I would say like no, I would skip this profile because he would be more helpful when we scale."),
            TranscriptSegment(id: "c13", timestamp: "21:09", speaker: "Meeting", text: "So the next was that go to market, kind of that sales advisor?"),
            TranscriptSegment(id: "c14", timestamp: "26:17", speaker: "Meeting", text: "Okay, amazing. So, Luke Miller. Okay, cool. We'll go with Luke Miller."),
            TranscriptSegment(id: "c15", timestamp: "27:20", speaker: "You", text: "I'll do it post this call. I'll complete it within the end of the today."),
            TranscriptSegment(id: "c16", timestamp: "30:13", speaker: "Meeting", text: "So if you could send me your pitch deck, your LinkedIn page, and then your company website."),
            TranscriptSegment(id: "c17", timestamp: "30:40", speaker: "You", text: "Okay, I'll do that then.")
        ])
        precondition(!connectd.brief.lowercased().contains("yeah yeah"))
        precondition(!connectd.brief.lowercased().contains("know know"))
        precondition(!connectd.brief.lowercased().contains("let's do the advisors first"))
        precondition(connectd.brief.lowercased().contains("advisor") || connectd.brief.lowercased().contains("fundraising"))
        precondition(connectd.decisions.contains { $0.text.lowercased().contains("luke miller") })
        precondition(connectd.decisions.contains { $0.text.lowercased().contains("skip") })
        precondition(connectd.decisions.count <= 8)
        precondition(!connectd.decisions.contains { $0.text.lowercased().contains("do the advisors first") })

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
        precondition(markdown.contains("Ship the private alpha on Friday."))
        precondition(!markdown.contains("Evidence:"))
        precondition(markdown.contains("## Transcript"))
        precondition(MeetingMarkdownExporter.fileName(for: meeting) == "Private-alpha-review.md")
        let markdownWithoutDecisions = MeetingMarkdownExporter.markdown(for: meeting, includeDecisions: false)
        precondition(!markdownWithoutDecisions.contains("## Decisions"))
        print("Meeting note cleanup, decision cap, and Markdown export checks passed")
    }
}
