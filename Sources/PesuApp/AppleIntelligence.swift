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
            Summarise this meeting using plain text only. Do not use Markdown, quotation marks, emoji, decorative symbols, or invented facts.
            Use this exact structure:
            Brief: one short, natural paragraph
            Decisions:
            S1: a decision supported by transcript segment S1
            Actions:
            one action per line
            Omit Decisions or Actions when the transcript does not support them. Keep each source label matched to the segment that supports it.
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
