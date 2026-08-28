import Foundation
import FoundationModels
import Speech

enum AppleServiceStatus: Equatable {
    case available
    case unavailable(String)
}

@available(macOS 26.0, *)
actor AppleIntelligence {
    func modelStatus() -> AppleServiceStatus {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                return .unavailable("Apple Intelligence is not enabled")
            case .deviceNotEligible:
                return .unavailable("This Mac does not support Apple Intelligence")
            case .modelNotReady:
                return .unavailable("The Apple Intelligence model is not ready")
            @unknown default:
                return .unavailable("Apple Intelligence is unavailable")
            }
        }
    }

    func speechStatus(locale: Locale = .current) async -> AppleServiceStatus {
        await SpeechTranscriber.supportedLocale(equivalentTo: locale) == nil
            ? .unavailable("The current language is not installed for Apple Speech.")
            : .available
    }

    func summarize(transcript: String) async throws -> String {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw IntelligenceError.modelUnavailable
        }
        let segmentCount = transcript
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { $0.range(of: #"^S\d+\s*\|"#, options: .regularExpression) != nil }
            .count
        let session = LanguageModelSession(
            model: model,
            instructions: """
            You summarise meetings from labelled transcript lines. Each line begins with S1, S2, and so on through S\(max(segmentCount, 1)).

            Output plain text only. No Markdown, quotation marks, emoji, bullets, numbering, or decorative symbols.

            Rules:
            - Use only facts explicitly stated in the transcript. Never invent names, dates, numbers, commitments, or outcomes.
            - Ignore filler, greetings, and unclear fragments. If the transcript is mostly small talk, say that honestly in the Brief.
            - Do not copy transcript lines verbatim into the Brief. Write a concise summary in your own words.
            - Do not use vague filler such as "The meeting discussed various topics" or "Participants talked about several things."

            Use this exact structure:

            Brief: Two to four sentences covering what the meeting was about, the main topics raised, and any stated outcomes or next steps. Be specific and useful.

            Decisions: List only explicit agreements or commitments someone made. Each line must begin with the supporting segment label, for example "S3: We will ship the alpha on Friday." Use only labels that exist in the transcript (S1 through S\(max(segmentCount, 1))). Omit this entire section when no explicit decision was made. Do not list opinions, questions, general discussion, or restatements of the Brief.

            Actions: List only concrete tasks someone committed to do, one per line. Omit this section when none were stated.
            """
        )
        let response = try await session.respond(to: transcript)
        return response.content
    }

    enum IntelligenceError: LocalizedError {
        case modelUnavailable

        var errorDescription: String? {
            "Apple Intelligence is not available on this Mac right now."
        }
    }
}
