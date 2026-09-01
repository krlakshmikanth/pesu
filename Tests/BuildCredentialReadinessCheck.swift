import Foundation

@main
enum BuildCredentialReadinessCheck {
    static func main() {
        precondition(BuildCredentialReadiness.evaluate(
            daytona: .configured,
            provider: .openAI,
            openAI: .configured,
            azureOpenAI: .missing,
            hasValidAzureConfiguration: false
        ) == .ready)
        precondition(BuildCredentialReadiness.evaluate(
            daytona: .missing,
            provider: .openAI,
            openAI: .configured,
            azureOpenAI: .missing,
            hasValidAzureConfiguration: false
        ) == .missing(["Daytona"]))
        precondition(BuildCredentialReadiness.evaluate(
            daytona: .configured,
            provider: .openAI,
            openAI: .missing,
            azureOpenAI: .configured,
            hasValidAzureConfiguration: true
        ) == .missing(["OpenAI"]))
        precondition(BuildCredentialReadiness.evaluate(
            daytona: .missing,
            provider: .openAI,
            openAI: .missing,
            azureOpenAI: .configured,
            hasValidAzureConfiguration: true
        ) == .missing(["Daytona", "OpenAI"]))
        precondition(BuildCredentialReadiness.evaluate(
            daytona: .unavailable,
            provider: .openAI,
            openAI: .configured,
            azureOpenAI: .missing,
            hasValidAzureConfiguration: false
        ) == .keychainUnavailable)
        precondition(BuildCredentialReadiness.evaluate(
            daytona: .configured,
            provider: .azureOpenAI,
            openAI: .missing,
            azureOpenAI: .configured,
            hasValidAzureConfiguration: true
        ) == .ready)
        precondition(BuildCredentialReadiness.evaluate(
            daytona: .configured,
            provider: .azureOpenAI,
            openAI: .configured,
            azureOpenAI: .missing,
            hasValidAzureConfiguration: false
        ) == .missing(["Azure OpenAI", "Azure OpenAI settings"]))
        precondition(BuildCredentialReadiness.evaluate(
            daytona: .configured,
            provider: .azureOpenAI,
            openAI: .configured,
            azureOpenAI: .unavailable,
            hasValidAzureConfiguration: true
        ) == .keychainUnavailable)
        print("Build credential readiness checks passed")
    }
}
