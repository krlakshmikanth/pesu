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

    private static let preferredDecisionCount = 5
    private static let maximumDecisionCount = 8

    private static let decisionLeadPattern = try! NSRegularExpression(
        pattern: #"^(?:(?:we|i|the team|everyone)\s+(?:will|should|need to|have to|are going to|are gonna|agreed to|decided to)|(?:we'll|i'll|lets|let's)|(?:agreed to|decided to|approved|committed to|plan to|need to|have to|going to|signed off on))\s+"#,
        options: [.caseInsensitive]
    )

    private static let genericBriefPhrases = [
        "the meeting discussed", "participants discussed", "the team discussed",
        "various topics", "general discussion", "several things", "a number of topics",
        "talked about a variety", "covered a range", "meeting was about",
        "conversation covered", "no clear decisions", "no specific decisions",
        "yeah yeah", "know know"
    ]

    private static let lowQualityDecisionPhrases = [
        "discussed the", "talked about the", "talked about", "mentioned the",
        "mentioned that", "went over the", "went over", "covered the", "reviewed the",
        "looked at the", "the meeting", "participants", "general discussion",
        "various topics", "no decision", "no clear decision", "nothing was decided",
        "unclear what", "it seems", "it appears", "might be", "could be",
        "possibly", "maybe we should", "we should think about", "good point",
        "sounds good", "makes sense", "circle back", "take a look", "have a think",
        "do the advisors first", "get through that"
    ]

    private static let stopWords: Set<String> = [
        "the", "and", "for", "that", "this", "with", "will", "have", "from", "they",
        "been", "were", "said", "each", "which", "their", "about", "would", "there",
        "could", "other", "into", "more", "some", "what", "when", "your", "also",
        "than", "then", "them", "these", "those", "are", "was", "not", "but", "can",
        "just", "like", "very", "really", "going"
    ]

    static func process(rawResponse: String, transcript: [TranscriptSegment]) -> ProcessedMeetingNotes {
        let legacyStatus = rawResponse.lowercased()
        if legacyStatus.hasPrefix("live transcript captured locally") ||
            legacyStatus.hasPrefix("recording saved locally") {
            return processFromTranscript(transcript)
        }

        var section = Section.brief
        var brief: [String] = []
        var decisions: [String] = []
        var sawDecisionSection = false

        for rawLine in rawResponse.components(separatedBy: .newlines) {
            var line = cleanLine(rawLine)
            guard !line.isEmpty else { continue }

            if let parsed = sectionPrefix(in: line) {
                section = parsed.section
                if section == .decisions { sawDecisionSection = true }
                line = parsed.remainder
                if line.isEmpty { continue }
            } else if let heading = headingSection(for: line) {
                section = heading
                if section == .decisions { sawDecisionSection = true }
                continue
            }

            switch section {
            case .brief:
                brief.append(line)
            case .decisions:
                let decisionText = removeSourceIndex(from: line)
                if !decisionText.isEmpty { decisions.append(decisionText) }
            case .actions:
                continue
            }
        }

        let incomingBrief = cleanDisplayText(brief.joined(separator: " "))
        let resolvedBrief = resolveBrief(incomingBrief, transcript: transcript)
        var resolvedDecisions = filterDecisions(
            decisions.compactMap { text -> Decision? in
                let cleaned = distillDecisionText(cleanDisplayText(text))
                guard isUsefulDecisionText(cleaned) else { return nil }
                guard isGrounded(cleaned, in: transcript) else { return nil }
                return Decision(id: "00", text: cleaned, evidenceSegmentID: "")
            }
        )

        if resolvedDecisions.isEmpty, !sawDecisionSection, !transcript.isEmpty, !isUsefulBrief(incomingBrief, transcript: transcript) {
            resolvedDecisions = extractDecisions(from: transcript)
        }

        return ProcessedMeetingNotes(brief: resolvedBrief, decisions: resolvedDecisions)
    }

    static func refineStoredDecisions(_ decisions: [Decision], transcript: [TranscriptSegment]) -> [Decision] {
        let cleaned = decisions.compactMap { decision -> Decision? in
            let text = distillDecisionText(cleanDisplayText(decision.text))
            guard isUsefulDecisionText(text) else { return nil }
            if !transcript.isEmpty, !isGrounded(text, in: transcript) { return nil }
            return Decision(id: decision.id, text: text, evidenceSegmentID: "")
        }
        return filterDecisions(cleaned)
    }

    static func processFromTranscript(_ transcript: [TranscriptSegment]) -> ProcessedMeetingNotes {
        ProcessedMeetingNotes(
            brief: fallbackBrief(from: transcript),
            decisions: extractDecisions(from: transcript)
        )
    }

    static func fallbackBrief(from transcript: [TranscriptSegment]) -> String {
        MeetingNotesSynthesis.brief(from: transcript)
    }

    static func extractDecisions(from transcript: [TranscriptSegment]) -> [Decision] {
        filterDecisions(MeetingNotesSynthesis.extractDecisions(from: transcript))
    }

    static func transcriptForSummarization(_ transcript: [TranscriptSegment]) -> String {
        MeetingNotesSynthesis.transcriptForSummarization(transcript)
    }

    static func numberedDecisions(_ decisions: [Decision]) -> [Decision] {
        decisions.enumerated().map { index, decision in
            Decision(id: String(format: "%02d", index + 1), text: decision.text, evidenceSegmentID: "")
        }
    }

    static func distillCommitment(_ text: String) -> String {
        distillDecisionText(text)
    }

    static func tokenOverlap(_ lhs: String, _ rhs: String) -> Double {
        let left = tokens(in: lhs, minimumLength: 3)
        let right = tokens(in: rhs, minimumLength: 3)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        return Double(left.intersection(right).count) / Double(min(left.count, right.count))
    }

    static func capitalizeFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
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

    static func isUsefulDecisionText(_ text: String) -> Bool {
        guard text.count >= 12 else { return false }
        if text.hasSuffix("?") { return false }
        let lower = text.lowercased()
        if lowQualityDecisionPhrases.contains(where: { lower.contains($0) }) { return false }
        if lower.hasPrefix("discuss") || lower.hasPrefix("talk about") || lower.hasPrefix("mention") { return false }
        if MeetingNotesSynthesis.isFillerHeavy(text) { return false }
        let wordCount = lower.split(whereSeparator: \.isWhitespace).count
        return wordCount >= 3 && wordCount <= 28
    }

    private static func resolveBrief(_ briefText: String, transcript: [TranscriptSegment]) -> String {
        let cleaned = cleanDisplayText(briefText)
        if cleaned.isEmpty || !isUsefulBrief(cleaned, transcript: transcript) {
            return fallbackBrief(from: transcript)
        }
        return cleaned
    }

    private static func isUsefulBrief(_ brief: String, transcript: [TranscriptSegment]) -> Bool {
        guard brief.count >= 24 else { return false }
        let lower = brief.lowercased()
        if genericBriefPhrases.contains(where: { lower.contains($0) }) { return false }
        if MeetingNotesSynthesis.isFillerHeavy(brief) { return false }
        if isVerbatimTranscriptCopy(brief, transcript: transcript) { return false }
        if transcript.isEmpty { return true }
        return isGrounded(brief, in: transcript, minimumOverlap: 0.12)
    }

    private static func distillDecisionText(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        if let match = decisionLeadPattern.firstMatch(in: result, options: [], range: range),
           let swiftRange = Range(match.range, in: result) {
            result = String(result[swiftRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return capitalizeFirst(result.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: "•*-–—,;:")
        )))
    }

    private static func filterDecisions(_ decisions: [Decision]) -> [Decision] {
        var unique: [Decision] = []
        for decision in decisions {
            guard isUsefulDecisionText(decision.text) else { continue }
            if unique.contains(where: { tokenOverlap($0.text, decision.text) >= 0.7 }) { continue }
            unique.append(decision)
        }

        let ranked = unique.sorted { teamImportance($0.text) > teamImportance($1.text) }
        if ranked.count <= preferredDecisionCount {
            return numberedDecisions(ranked)
        }
        let important = ranked.filter { teamImportance($0.text) >= 4 }
        let selected = important.count >= preferredDecisionCount
            ? Array(important.prefix(maximumDecisionCount))
            : Array(ranked.prefix(preferredDecisionCount))
        return numberedDecisions(selected)
    }

    private static func teamImportance(_ text: String) -> Int {
        let lower = text.lowercased()
        var score = 2
        if lower.hasPrefix("proceed with") { score += 4 }
        if lower.hasPrefix("skip ") { score += 3 }
        if lower.hasPrefix("complete") || lower.hasPrefix("send") || lower.hasPrefix("share") { score += 3 }
        if lower.rangeOfCharacter(from: .decimalDigits) != nil { score += 3 }
        for marker in ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
                       "january", "february", "march", "april", "june", "july", "august",
                       "september", "october", "november", "december"] {
            if lower.contains(marker) { score += 3; break }
        }
        for cue in ["decided", "agreed", "approved", "ship", "launch", "hire", "budget", "deadline", "owner"] {
            if lower.contains(cue) { score += 2 }
        }
        if lower.contains("look at") || lower.contains("check the") || lower.contains("follow up") { score -= 2 }
        return score
    }

    private static func isGrounded(_ text: String, in transcript: [TranscriptSegment], minimumOverlap: Double = 0.25) -> Bool {
        guard !transcript.isEmpty else { return true }
        let textTokens = tokens(in: text, minimumLength: 3)
        guard !textTokens.isEmpty else { return false }
        let transcriptTokens = Set(transcript.flatMap { tokens(in: $0.text, minimumLength: 3) })
        let overlap = Double(textTokens.intersection(transcriptTokens).count) / Double(textTokens.count)
        return overlap >= minimumOverlap
    }

    private static func isVerbatimTranscriptCopy(_ brief: String, transcript: [TranscriptSegment]) -> Bool {
        let briefLower = brief.lowercased()
        let segments = transcript
            .map { cleanDisplayText($0.text).lowercased() }
            .filter { $0.count >= 20 }
        if segments.contains(where: { briefLower == $0 || briefLower.contains($0) }) {
            return true
        }
        let joined = segments.prefix(3).joined(separator: " ")
        return !joined.isEmpty && (briefLower == joined || briefLower.contains(joined))
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

    private static func removeSourceIndex(from line: String) -> String {
        line.replacingOccurrences(of: #"^S\d+\s*[:|.-]?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    private static func tokens(in text: String, minimumLength: Int = 3) -> Set<String> {
        Set(text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= minimumLength && !stopWords.contains($0) })
    }
}
