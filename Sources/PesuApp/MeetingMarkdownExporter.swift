import Foundation

enum MeetingMarkdownExporter {
    static func markdown(for meeting: Meeting) -> String {
        var lines = [
            "# \(meeting.title)",
            "",
            "- Date: \(meeting.startedAt.formatted(date: .complete, time: .shortened))",
            "- Duration: \(meeting.duration.minuteString)"
        ]
        if !meeting.participants.isEmpty {
            lines.append("- Participants: \(meeting.participants.joined(separator: ", "))")
        }
        lines += ["", "## Brief", "", MeetingNotesProcessor.cleanDisplayText(meeting.summary)]

        if !meeting.decisions.isEmpty {
            lines += ["", "## Decisions", ""]
            for decision in meeting.decisions {
                let source = meeting.transcript.first { $0.id == decision.evidenceSegmentID }
                let evidence = source.map { " Evidence: \($0.timestamp), \($0.speaker)." } ?? ""
                lines.append("- \(decision.text)\(evidence)")
            }
        }

        if !meeting.transcript.isEmpty {
            lines += ["", "## Transcript", ""]
            for segment in meeting.transcript {
                lines.append("- \(segment.timestamp) — \(segment.speaker): \(segment.text)")
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    static func fileName(for meeting: Meeting) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let safeTitle = meeting.title.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "" }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
        return "\(safeTitle.isEmpty ? "meeting" : safeTitle).md"
    }
}
