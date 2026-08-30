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
        provider: BuildAIProvider,
        openAI: APIKeyAvailability,
        azureOpenAI: APIKeyAvailability,
        hasValidAzureConfiguration: Bool
    ) -> BuildCredentialReadiness {
        let selectedCredential = provider == .openAI ? openAI : azureOpenAI
        if daytona == .unavailable || selectedCredential == .unavailable {
            return .keychainUnavailable
        }
        var providers: [String] = []
        if daytona == .missing { providers.append("Daytona") }
        switch provider {
        case .openAI:
            if openAI == .missing { providers.append("OpenAI") }
        case .azureOpenAI:
            if azureOpenAI == .missing { providers.append("Azure OpenAI") }
            if !hasValidAzureConfiguration { providers.append("Azure OpenAI settings") }
        }
        return providers.isEmpty ? .ready : .missing(providers)
    }
}
