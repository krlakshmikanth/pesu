import Foundation

struct ProcessedMeetingNotes: Equatable {
    let brief: String
    let decisions: [Decision]
}

enum MeetingNotesProcessor {
    private enum Section {
        case brief
        case decisions
        case actions
    }

    static func process(rawResponse: String, transcript: [TranscriptSegment]) -> ProcessedMeetingNotes {
        let legacyStatus = rawResponse.lowercased()
        if legacyStatus.hasPrefix("live transcript captured locally") ||
            legacyStatus.hasPrefix("recording saved locally") {
            return ProcessedMeetingNotes(brief: fallbackBrief(from: transcript), decisions: [])
        }
        var section = Section.brief
        var brief: [String] = []
        var decisions: [(text: String, sourceIndex: Int?)] = []

        for rawLine in rawResponse.components(separatedBy: .newlines) {
            var line = cleanLine(rawLine)
            guard !line.isEmpty else { continue }

            if let parsed = sectionPrefix(in: line) {
                section = parsed.section
                line = parsed.remainder
                if line.isEmpty { continue }
            } else if let heading = headingSection(for: line) {
                section = heading
                continue
            }

            switch section {
            case .brief:
                brief.append(line)
            case .decisions:
                let source = sourceIndex(in: line)
                let decisionText = removeSourceIndex(from: line)
                if !decisionText.isEmpty { decisions.append((decisionText, source)) }
            case .actions:
                continue
            }
        }

        let briefText = cleanDisplayText(brief.joined(separator: " "))
        let resolvedBrief = briefText.isEmpty ? fallbackBrief(from: transcript) : briefText
        let resolvedDecisions = decisions.enumerated().map { offset, item in
            let evidence = evidenceSegmentID(
                for: item.text,
                requestedIndex: item.sourceIndex,
                transcript: transcript,
                fallbackIndex: offset
            )
            return Decision(
                id: String(format: "%02d", offset + 1),
                text: cleanDisplayText(item.text),
                evidenceSegmentID: evidence
            )
        }
        return ProcessedMeetingNotes(brief: resolvedBrief, decisions: resolvedDecisions)
    }

    static func cleanDisplayText(_ value: String) -> String {
        var result = value
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        result = String(result.unicodeScalars.filter {
            !$0.properties.isEmojiPresentation && $0.value != 0xFE0F && $0.value != 0x200D
        })
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: "•*-–—,;:")
        ))
    }

    static func fallbackBrief(from transcript: [TranscriptSegment]) -> String {
        let spokenText = transcript.prefix(3)
            .map { cleanDisplayText($0.text) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return spokenText.isEmpty ? "No speech was captured for this recording." : spokenText
    }

    private static func cleanLine(_ raw: String) -> String {
        var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        line = line.replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^(?:[-*•–—]|\d+[.)])\s+"#, with: "", options: .regularExpression)
        return cleanDisplayText(line)
    }

    private static func headingSection(for line: String) -> Section? {
        let heading = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        switch heading {
        case "summary", "brief", "in brief": return .brief
        case "decision", "decisions": return .decisions
        case "action", "actions", "action item", "action items": return .actions
        default: return nil
        }
    }

    private static func sectionPrefix(in line: String) -> (section: Section, remainder: String)? {
        let prefixes: [(String, Section)] = [
            ("summary:", .brief), ("brief:", .brief), ("in brief:", .brief),
            ("decisions:", .decisions), ("decision:", .decisions),
            ("actions:", .actions), ("action items:", .actions), ("action:", .actions)
        ]
        let lower = line.lowercased()
        guard let (prefix, section) = prefixes.first(where: { lower.hasPrefix($0.0) }) else { return nil }
        return (section, String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces))
    }

    private static func sourceIndex(in line: String) -> Int? {
        guard let range = line.range(of: #"^S(\d+)\s*[:|.-]?\s*"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let token = line[range].uppercased()
        return Int(token.dropFirst().prefix { $0.isNumber }).map { $0 - 1 }
    }

    private static func removeSourceIndex(from line: String) -> String {
        line.replacingOccurrences(of: #"^S\d+\s*[:|.-]?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    private static func evidenceSegmentID(
        for decision: String,
        requestedIndex: Int?,
        transcript: [TranscriptSegment],
        fallbackIndex: Int
    ) -> String {
        if let requestedIndex, transcript.indices.contains(requestedIndex) {
            return transcript[requestedIndex].id
        }
        guard !transcript.isEmpty else { return "" }
        let decisionTokens = tokens(in: decision)
        let scored = transcript.map { segment in
            (segment, decisionTokens.intersection(tokens(in: segment.text)).count)
        }
        if let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 { return best.0.id }
        return transcript[min(fallbackIndex, transcript.count - 1)].id
    }

    private static func tokens(in text: String) -> Set<String> {
        Set(text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 })
    }
}
