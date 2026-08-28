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
        let session = LanguageModelSession(
            model: model,
            instructions: """
            You write executive meeting notes for people who were not in the room.

            The transcript is noisy speech-to-text. Ignore filler (um, uh, yeah, you know), greetings, and broken fragments. Repair obvious names when surrounding words make them clear. Never invent people, companies, dates, or outcomes.

            Write original sentences. Do not copy or stitch transcript lines. Do not write "This meeting focused on yeah" or similar filler.

            Output plain text only, with this exact structure:

            Brief: Two to four original sentences covering why the meeting happened, which options were chosen or skipped, and what happens next.

            Decisions: Three to eight outcome sentences, one per line. Prefer 5. Include only agreements that change team work, such as who to proceed with, who to skip, and concrete next steps. Omit agenda chatter such as "let's do the advisors first." Omit this section when nothing was decided.

            Quality example:
            Brief: The team reviewed Connectd advisor candidates for fundraising, clinical safety, and go-to-market. They preferred the grants-focused fundraising profile and the more clinical healthcare advisor, and chose the early-stage SaaS sales advisor. Next, the founders complete the platform profile and send the pitch deck, LinkedIn, and website so introductions can start.
            Decisions:
            Proceed with Adrian for fundraising.
            Prefer Nilo for clinical safety.
            Proceed with Luke Miller for go-to-market.
            Complete the Connectd profile today.
            Send the pitch deck, LinkedIn, and website so advisor introductions can begin.
            """
        )
        let response = try await session.respond(
            to: "Write the meeting notes from this cleaned transcript:\n\n\(transcript)"
        )
        return response.content
    }

    enum IntelligenceError: LocalizedError {
        case modelUnavailable

        var errorDescription: String? {
            "Apple Intelligence is not available on this Mac right now."
        }
    }
}
