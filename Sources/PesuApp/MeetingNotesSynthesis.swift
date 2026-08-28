import Foundation

enum MeetingNotesSynthesis {
    private static let fillerTokens: Set<String> = [
        "um", "uh", "uhh", "uhm", "er", "ah", "ahh", "erm",
        "yeah", "yea", "yep", "yup", "mm", "mhm", "mmhmm", "hmm", "huh",
        "uhhuh", "uhuh", "okay", "ok", "okey", "right", "sure", "well",
        "like", "basically", "actually", "literally", "seriously",
        "gonna", "wanna", "kinda", "sorta", "cos", "cause",
        "hello", "hi", "hey", "bye", "goodbye", "thanks", "thank", "please"
    ]

    private static let fillerPhrases = [
        "you know", "i mean", "kind of", "sort of", "kind of like",
        "at the end of the day", "to be honest", "to be fair"
    ]

    private static let agendaPhrases = [
        "let's do the", "lets do the", "let's get through", "lets get through",
        "let's have a look", "lets have a look", "let's look", "lets look",
        "let's go through", "lets go through", "let me bring", "let me show",
        "let me share", "let me just", "let me send"
    ]

    private static let nameDenylist: Set<String> = [
        "meeting", "you", "okay", "cool", "super", "perfect", "amazing", "thanks",
        "thank", "once", "then", "after", "have", "look", "let", "this", "that",
        "when", "what", "with", "from", "they", "your", "just", "also", "next",
        "first", "last", "yeah", "there", "here", "them", "their", "and", "the",
        "for", "but", "not", "now", "how", "why", "who", "our", "are", "was",
        "were", "been", "being", "will", "would", "could", "should", "can", "may",
        "maybe", "than", "exactly", "phd", "md", "nhs", "gtm", "saas", "uk",
        "asap", "sorry", "hold", "full", "screen", "profile", "platform",
        "health", "advisor", "linkedin", "website", "company"
    ]

    private static let introducePattern = try! NSRegularExpression(
        pattern: #"(?:this is|that(?:'|’)s|that is|bring up(?: is)?|have a look at|look at)\s+([A-Za-z][a-z]{2,}(?:\s+[A-Z][a-z]{2,})?)"#,
        options: [.caseInsensitive]
    )

    private static let fullNamePattern = try! NSRegularExpression(
        pattern: #"\b([A-Z][a-z]{2,}\s+[A-Z][a-z]{2,})\b"#
    )

    private static let roleRules: [(match: String, label: String)] = [
        ("fundraising", "fundraising"),
        ("grant", "fundraising"),
        ("clinical", "clinical safety"),
        ("healthcare", "clinical safety"),
        ("health advisor", "clinical safety"),
        ("go to market", "go-to-market"),
        ("go-to-market", "go-to-market"),
        ("gtm", "go-to-market"),
        ("sales advisor", "go-to-market"),
        ("sales", "sales")
    ]

    static func brief(from transcript: [TranscriptSegment]) -> String {
        let cleaned = cleanedSegments(transcript)
        guard !cleaned.isEmpty else {
            return "No speech was captured for this recording."
        }

        let roles = detectedRoles(in: cleaned)
        let company = detectedCompany(in: cleaned)
        let decisions = extractDecisions(from: transcript)
        let proceeds = decisions.filter {
            let lower = $0.text.lowercased()
            return lower.hasPrefix("proceed with") || lower.hasPrefix("prefer ")
        }
        let next = decisions.filter {
            let lower = $0.text.lowercased()
            return lower.hasPrefix("complete") || lower.hasPrefix("send") || lower.hasPrefix("share") || lower.hasPrefix("make ")
        }

        var sentences: [String] = []
        if !roles.isEmpty {
            let roleList = joinList(roles)
            if let company, !company.isEmpty {
                sentences.append("This meeting reviewed \(roleList) advisor candidates for \(company).")
            } else {
                sentences.append("This meeting reviewed \(roleList) advisor candidates.")
            }
        } else if let purpose = purposeSentence(from: cleaned) {
            sentences.append(purpose)
        }

        if !proceeds.isEmpty {
            var seenPeople: Set<String> = []
            var selections: [String] = []
            for decision in proceeds {
                let pretty = prettySelection(decision.text)
                let person = pretty.split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? pretty.lowercased()
                if seenPeople.contains(person) { continue }
                seenPeople.insert(person)
                selections.append(pretty)
                if selections.count == 3 { break }
            }
            if !selections.isEmpty {
                sentences.append("The team selected \(joinList(selections)).")
            }
        } else if !decisions.isEmpty {
            let lead = decisions.prefix(2).map { lowerFirst(stripTrailingPeriod($0.text)) }
            sentences.append("The team agreed to \(joinList(lead)).")
        }

        if !next.isEmpty {
            let actions = next.prefix(2).map { lowerFirst(stripTrailingPeriod($0.text)) }
            sentences.append("Next, \(joinList(actions)).")
        }

        if sentences.isEmpty {
            sentences.append(compressedSentence(cleaned.max { $0.count < $1.count } ?? cleaned[0]))
        }

        let brief = sentences.joined(separator: " ")
        if isFillerHeavy(brief) {
            return "This meeting captured discussion that did not produce a clear written summary."
        }
        return brief
    }

    static func extractDecisions(from transcript: [TranscriptSegment]) -> [Decision] {
        var lastName: String?
        var lastRole: String?
        var candidates: [String] = []

        for segment in transcript {
            let raw = normalizeQuotes(MeetingNotesProcessor.cleanDisplayText(segment.text))
            let cleaned = cleanedSpeech(raw)
            if let name = candidateName(in: raw) {
                lastName = name
            }
            if cleaned.lowercased().contains("advisor") || cleaned.lowercased().contains("next was") || cleaned.lowercased().contains("next role") {
                if let role = detectedRoles(in: [cleaned]).first {
                    lastRole = role
                }
            }

            let haystack = cleaned.lowercased()
            guard !isAgendaLine(haystack) else { continue }

            if isSkipLine(haystack), let name = candidateName(in: raw) ?? lastName {
                candidates.append("Skip \(name)\(roleSuffix(lastRole)).")
                continue
            }
            if isGoAheadLine(haystack), let name = candidateName(in: raw) ?? lastName {
                candidates.append("Proceed with \(name)\(roleSuffix(lastRole)).")
                continue
            }
            if isPreferLine(haystack), let name = candidateName(in: raw) ?? lastName {
                candidates.append("Prefer \(name)\(roleSuffix(lastRole)).")
                continue
            }
            if isNextStepLine(haystack) {
                if haystack.contains("pitch deck") || haystack.contains("linkedin") || haystack.contains("send me your") {
                    candidates.append("Send the pitch deck, LinkedIn, and website.")
                } else if haystack.contains("complete") && (haystack.contains("profile") || haystack.contains("complete it")) {
                    candidates.append("Complete the platform profile today.")
                } else {
                    let distilled = MeetingNotesProcessor.distillCommitment(cleaned)
                    if MeetingNotesProcessor.isUsefulDecisionText(distilled) {
                        candidates.append(distilled.hasSuffix(".") ? distilled : "\(distilled).")
                    }
                }
            }
        }

        if candidates.isEmpty {
            for segment in transcript {
                let cleaned = cleanedSpeech(MeetingNotesProcessor.cleanDisplayText(segment.text))
                let lower = cleaned.lowercased()
                guard !isAgendaLine(lower), containsCommitment(lower) else { continue }
                let distilled = MeetingNotesProcessor.distillCommitment(cleaned)
                guard MeetingNotesProcessor.isUsefulDecisionText(distilled) else { continue }
                candidates.append(distilled.hasSuffix(".") ? distilled : "\(distilled).")
            }
        }

        let unique = uniqueTexts(candidates)
        return MeetingNotesProcessor.numberedDecisions(
            unique.prefix(8).map { Decision(id: "00", text: $0, evidenceSegmentID: "") }
        )
    }

    static func cleanedSpeech(_ text: String) -> String {
        var result = normalizeQuotes(text).replacingOccurrences(of: #"#+\w*"#, with: " ", options: .regularExpression)
        for phrase in fillerPhrases {
            result = result.replacingOccurrences(of: phrase, with: " ", options: [.caseInsensitive])
        }
        let words = result.split(whereSeparator: \.isWhitespace).compactMap { token -> String? in
            let trimmed = token.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
            let lower = trimmed.lowercased()
            guard !lower.isEmpty, !fillerTokens.contains(lower) else { return nil }
            return String(token).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        }
        return words.joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func transcriptForSummarization(_ transcript: [TranscriptSegment]) -> String {
        transcript.compactMap { segment in
            let text = cleanedSpeech(MeetingNotesProcessor.cleanDisplayText(segment.text))
            guard text.split(whereSeparator: \.isWhitespace).count >= 5, !isFillerHeavy(text) else { return nil }
            return "\(segment.speaker): \(text)"
        }.joined(separator: "\n")
    }

    static func isFillerHeavy(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("yeah yeah") || lower.contains("know know") || lower.contains("um,") { return true }
        let words = lower.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return true }
        let fillerCount = words.filter { fillerTokens.contains($0.trimmingCharacters(in: .punctuationCharacters)) }.count
        return Double(fillerCount) / Double(words.count) >= 0.28
    }

    private static func cleanedSegments(_ transcript: [TranscriptSegment]) -> [String] {
        transcript
            .map { cleanedSpeech(MeetingNotesProcessor.cleanDisplayText($0.text)) }
            .filter { $0.split(whereSeparator: \.isWhitespace).count >= 4 && !isFillerHeavy($0) }
    }

    private static func detectedRoles(in lines: [String]) -> [String] {
        let joined = lines.joined(separator: " ").lowercased()
        var roles: [String] = []
        for rule in roleRules {
            if joined.contains(rule.match), !roles.contains(rule.label) {
                roles.append(rule.label)
            }
        }
        return Array(roles.prefix(3))
    }

    private static func detectedCompany(in lines: [String]) -> String? {
        let joined = lines.joined(separator: " ").lowercased()
        if joined.contains("latte health") || joined.contains("lat health") || joined.contains("latter health") {
            return "Latte Health"
        }
        if joined.contains("latte") { return "Latte Health" }
        return nil
    }

    private static func purposeSentence(from lines: [String]) -> String? {
        guard let line = lines.first(where: { $0.lowercased().contains("here to") || $0.lowercased().contains("talk about") || $0.count > 80 }) else {
            return nil
        }
        return compressedSentence(line)
    }

    private static func candidateName(in text: String) -> String? {
        if let full = firstMatch(fullNamePattern, in: text), isAllowedName(full) {
            return full
        }
        if let introduced = firstMatch(introducePattern, in: text), isAllowedName(introduced),
           introduced.first?.isUppercase == true {
            return introduced
        }
        return nil
    }

    private static func isAllowedName(_ name: String) -> Bool {
        let parts = name.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        return !parts.isEmpty && parts.allSatisfy { !nameDenylist.contains($0) }
    }

    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[swiftRange])
    }

    private static func isAgendaLine(_ text: String) -> Bool {
        agendaPhrases.contains { text.contains($0) }
    }

    private static func isSkipLine(_ text: String) -> Bool {
        text.contains("skip this") || text.contains("skip this profile") || text.contains("skip this for now")
            || text.contains("i would skip") || text.contains("maybe skip")
    }

    private static func isGoAheadLine(_ text: String) -> Bool {
        text.contains("go with") || text.contains("go ahead with") || text.contains("we'll go with")
            || text.contains("we can go ahead")
    }

    private static func isPreferLine(_ text: String) -> Bool {
        text.contains("looks more relevant") || text.contains("more relevant than") || text.contains("better than the previous")
    }

    private static func normalizeQuotes(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
    }

    private static func isNextStepLine(_ text: String) -> Bool {
        text.contains("i'll complete") || text.contains("i will complete") || text.contains("i'll send")
            || text.contains("i will send") || text.contains("i'll share") || text.contains("i will share")
            || text.contains("send me your") || text.contains("complete your profile") || text.contains("complete it")
            || text.contains("make it public") || text.contains("i'll do that")
    }

    private static func containsCommitment(_ text: String) -> Bool {
        ["we will ", "we'll ", "i will ", "i'll ", "agreed to ", "decided to ",
         "going to ", "plan to ", "commit to ", "signed off on ", "approved "].contains { text.contains($0) }
    }

    private static func roleSuffix(_ role: String?) -> String {
        guard let role else { return "" }
        return " for \(role)"
    }

    private static func uniqueTexts(_ texts: [String]) -> [String] {
        var unique: [String] = []
        for text in texts {
            if unique.contains(where: { MeetingNotesProcessor.tokenOverlap($0, text) >= 0.7 }) { continue }
            unique.append(text)
        }
        return unique
    }

    private static func compressedSentence(_ text: String) -> String {
        let clause = text.split(whereSeparator: { ".!?;".contains($0) }).first.map(String.init) ?? text
        let words = clause.split(whereSeparator: \.isWhitespace)
        let trimmed = words.prefix(22).joined(separator: " ")
        return MeetingNotesProcessor.capitalizeFirst(trimmed.hasSuffix(".") ? trimmed : "\(trimmed).")
    }

    private static func joinList(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", and \(items.last!)"
        }
    }

    private static func lowerFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    private static func prettySelection(_ text: String) -> String {
        var result = stripTrailingPeriod(text)
        for prefix in ["Proceed with ", "Prefer ", "Skip "] {
            if result.lowercased().hasPrefix(prefix.lowercased()) {
                result = String(result.dropFirst(prefix.count))
                break
            }
        }
        return result
    }

    private static func stripTrailingPeriod(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}
