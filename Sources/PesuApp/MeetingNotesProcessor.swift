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

    private static let fillerSegmentPattern = try! NSRegularExpression(
        pattern: #"^(?:um+|uh+|okay|ok|yeah|yes|no|thanks|thank you|right|sure|hello|hi|hey|bye|goodbye|hmm+|mhm+|mm-hmm)[\s.!,?-]*$"#,
        options: [.caseInsensitive]
    )

    private static let genericBriefPhrases = [
        "the meeting discussed",
        "participants discussed",
        "the team discussed",
        "various topics",
        "general discussion",
        "several things",
        "a number of topics",
        "talked about a variety",
        "covered a range",
        "meeting was about",
        "conversation covered",
        "no clear decisions",
        "no specific decisions"
    ]

    private static let lowQualityDecisionPhrases = [
        "discussed the",
        "talked about the",
        "talked about",
        "mentioned the",
        "mentioned that",
        "went over the",
        "went over",
        "covered the",
        "reviewed the",
        "looked at the",
        "the meeting",
        "participants",
        "general discussion",
        "various topics",
        "no decision",
        "no clear decision",
        "nothing was decided",
        "unclear what",
        "it seems",
        "it appears",
        "might be",
        "could be",
        "possibly",
        "maybe we should",
        "we should think about",
        "good point",
        "sounds good",
        "makes sense"
    ]

    private static let commitmentPatterns = [
        "we will ",
        "we'll ",
        "i will ",
        "i'll ",
        "let's ",
        "lets ",
        "agreed to ",
        "decided to ",
        "need to ",
        "have to ",
        "going to ",
        "plan to ",
        "commit to ",
        "signed off on ",
        "approved "
    ]

    static func process(rawResponse: String, transcript: [TranscriptSegment]) -> ProcessedMeetingNotes {
        let legacyStatus = rawResponse.lowercased()
        if legacyStatus.hasPrefix("live transcript captured locally") ||
            legacyStatus.hasPrefix("recording saved locally") {
            return processFromTranscript(transcript)
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
        let resolvedBrief = resolveBrief(briefText, transcript: transcript)
        var resolvedDecisions = filterDecisions(
            decisions.compactMap { item -> Decision? in
                let cleaned = cleanDisplayText(item.text)
                guard isUsefulDecisionText(cleaned) else { return nil }
                guard let evidenceID = evidenceSegmentID(
                    for: cleaned,
                    requestedIndex: item.sourceIndex,
                    transcript: transcript
                ) else { return nil }
                return Decision(id: "00", text: cleaned, evidenceSegmentID: evidenceID)
            },
            transcript: transcript
        )
        resolvedDecisions = numberedDecisions(resolvedDecisions)

        if resolvedDecisions.isEmpty, !transcript.isEmpty {
            return ProcessedMeetingNotes(brief: resolvedBrief, decisions: extractDecisions(from: transcript))
        }

        return ProcessedMeetingNotes(brief: resolvedBrief, decisions: resolvedDecisions)
    }

    static func refineStoredDecisions(_ decisions: [Decision], transcript: [TranscriptSegment]) -> [Decision] {
        let cleaned = decisions.compactMap { decision -> Decision? in
            let text = cleanDisplayText(decision.text)
            guard isUsefulDecisionText(text) else { return nil }
            let evidenceExists = transcript.contains { $0.id == decision.evidenceSegmentID }
            let evidenceID: String?
            if evidenceExists,
               let segment = transcript.first(where: { $0.id == decision.evidenceSegmentID }),
               evidenceScore(decision: text, segment: segment.text) >= minimumEvidenceScore {
                evidenceID = decision.evidenceSegmentID
            } else {
                evidenceID = evidenceSegmentID(for: text, requestedIndex: nil, transcript: transcript)
            }
            guard let evidenceID else { return nil }
            return Decision(id: decision.id, text: text, evidenceSegmentID: evidenceID)
        }
        return numberedDecisions(filterDecisions(cleaned, transcript: transcript))
    }

    static func processFromTranscript(_ transcript: [TranscriptSegment]) -> ProcessedMeetingNotes {
        ProcessedMeetingNotes(
            brief: fallbackBrief(from: transcript),
            decisions: extractDecisions(from: transcript)
        )
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
        let substantive = transcript
            .map { cleanDisplayText($0.text) }
            .filter { isSubstantiveSegment($0) }

        guard !substantive.isEmpty else {
            return "No speech was captured for this recording."
        }

        let commitmentLines = substantive.filter { containsCommitmentLanguage($0) }
        if !commitmentLines.isEmpty {
            let lead = commitmentLines.prefix(2).joined(separator: " ")
            if substantive.count > commitmentLines.count {
                let context = substantive
                    .filter { !commitmentLines.contains($0) }
                    .sorted { $0.count > $1.count }
                    .prefix(1)
                    .joined(separator: " ")
                if !context.isEmpty {
                    return "\(context) \(lead)".trimmingCharacters(in: .whitespaces)
                }
            }
            return lead
        }

        return substantive
            .sorted { $0.count > $1.count }
            .prefix(3)
            .reversed()
            .joined(separator: " ")
    }

    static func extractDecisions(from transcript: [TranscriptSegment]) -> [Decision] {
        let candidates = transcript.enumerated().compactMap { index, segment -> Decision? in
            let text = cleanDisplayText(segment.text)
            guard isUsefulDecisionText(text), containsCommitmentLanguage(text) else { return nil }
            return Decision(
                id: String(format: "%02d", index + 1),
                text: text,
                evidenceSegmentID: segment.id
            )
        }

        return numberedDecisions(filterDecisions(candidates, transcript: transcript))
    }

    private static func numberedDecisions(_ decisions: [Decision]) -> [Decision] {
        decisions.enumerated().map { index, decision in
            Decision(
                id: String(format: "%02d", index + 1),
                text: decision.text,
                evidenceSegmentID: decision.evidenceSegmentID
            )
        }
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
        if brief.hasSuffix("?") { return false }

        let briefTokens = tokens(in: brief, minimumLength: 2)
        guard !briefTokens.isEmpty else { return false }

        let transcriptTokens = Set(transcript.flatMap { tokens(in: $0.text, minimumLength: 2) })
        let overlap = Double(briefTokens.intersection(transcriptTokens).count) / Double(briefTokens.count)
        if overlap < 0.2 { return false }

        let verbatimOverlap = transcript
            .map { cleanDisplayText($0.text).lowercased() }
            .filter { !$0.isEmpty }
            .contains { segment in
                segment.count >= 20 && (brief.lowercased().contains(segment) || segment.contains(brief.lowercased()))
            }
        return !verbatimOverlap
    }

    private static func isUsefulDecisionText(_ text: String) -> Bool {
        guard text.count >= 12 else { return false }
        if text.hasSuffix("?") { return false }

        let lower = text.lowercased()
        if lowQualityDecisionPhrases.contains(where: { lower.contains($0) }) { return false }
        if lower.hasPrefix("discuss") || lower.hasPrefix("talk about") || lower.hasPrefix("mention") { return false }

        let wordCount = lower.split(whereSeparator: \.isWhitespace).count
        return wordCount >= 3
    }

    private static func isSubstantiveSegment(_ text: String) -> Bool {
        guard text.count >= 12 else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if fillerSegmentPattern.firstMatch(in: text, options: [], range: range) != nil { return false }
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        return wordCount >= 3
    }

    private static func containsCommitmentLanguage(_ text: String) -> Bool {
        let lower = text.lowercased()
        return commitmentPatterns.contains { lower.contains($0) }
    }

    private static func filterDecisions(_ decisions: [Decision], transcript: [TranscriptSegment]) -> [Decision] {
        var seen = Set<String>()
        return decisions.filter { decision in
            let key = decision.text.lowercased()
            guard !seen.contains(key) else { return false }
            guard transcript.contains(where: { $0.id == decision.evidenceSegmentID }) else { return false }
            guard let segment = transcript.first(where: { $0.id == decision.evidenceSegmentID }) else { return false }
            guard evidenceScore(decision: decision.text, segment: segment.text) >= minimumEvidenceScore else { return false }
            seen.insert(key)
            return true
        }
    }

    private static let minimumEvidenceScore = 3

    private static let stopWords: Set<String> = [
        "the", "and", "for", "that", "this", "with", "will", "have", "from", "they",
        "been", "were", "said", "each", "which", "their", "about", "would", "there",
        "could", "other", "into", "more", "some", "what", "when", "your", "also",
        "than", "then", "them", "these", "those", "are", "was", "not", "but", "can"
    ]

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
        transcript: [TranscriptSegment]
    ) -> String? {
        guard !transcript.isEmpty else { return nil }

        if let requestedIndex, transcript.indices.contains(requestedIndex) {
            let segment = transcript[requestedIndex]
            if evidenceScore(decision: decision, segment: segment.text) >= minimumEvidenceScore {
                return segment.id
            }
        }

        let best = transcript
            .map { ($0, evidenceScore(decision: decision, segment: $0.text)) }
            .max { lhs, rhs in
                if lhs.1 == rhs.1 { return lhs.0.timestamp > rhs.0.timestamp }
                return lhs.1 < rhs.1
            }

        guard let best, best.1 >= minimumEvidenceScore else { return nil }
        return best.0.id
    }

    private static func evidenceScore(decision: String, segment: String) -> Int {
        let decisionTokens = tokens(in: decision, minimumLength: 2)
        let segmentTokens = tokens(in: segment, minimumLength: 2)
        guard !decisionTokens.isEmpty, !segmentTokens.isEmpty else { return 0 }

        let shared = decisionTokens.intersection(segmentTokens)
        var score = shared.count * 2

        let decisionLower = decision.lowercased()
        let segmentLower = segment.lowercased()
        if segmentLower.contains(decisionLower) || decisionLower.contains(segmentLower) {
            score += 4
        }

        for token in shared where token.count >= 5 {
            score += 1
        }

        return score
    }

    private static func tokens(in text: String, minimumLength: Int = 3) -> Set<String> {
        Set(text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= minimumLength && !stopWords.contains($0) })
    }
}
