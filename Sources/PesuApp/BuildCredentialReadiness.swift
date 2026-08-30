import Foundation

enum APIKeyAvailability: Equatable, Sendable {
    case configured
    case missing
    case unavailable
}

enum BuildCredentialReadiness: Equatable, Sendable {
    case ready
    case missing([String])
    case keychainUnavailable

    static func evaluate(
        daytona: APIKeyAvailability,
        openAI: APIKeyAvailability
    ) -> BuildCredentialReadiness {
        if daytona == .unavailable || openAI == .unavailable {
            return .keychainUnavailable
        }
        var providers: [String] = []
        if daytona == .missing { providers.append("Daytona") }
        if openAI == .missing { providers.append("OpenAI") }
        return providers.isEmpty ? .ready : .missing(providers)
    }
}
