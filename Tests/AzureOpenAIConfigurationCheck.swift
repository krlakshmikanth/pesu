import Foundation

@main
enum AzureOpenAIConfigurationCheck {
    static func main() throws {
        let configuration = try AzureOpenAIConfiguration(
            endpoint: " https://My-Resource.openai.azure.com/openai/v1/ ",
            deployment: " landing-page-model "
        )
        precondition(configuration.endpoint == "https://my-resource.openai.azure.com/openai/v1")
        precondition(configuration.deployment == "landing-page-model")
        precondition(BuildAIProviderSelection.azureOpenAI(configuration).disclosure == "Azure OpenAI · my-resource.openai.azure.com")

        let suiteName = "com.lattelabs.pesu.tests.azure-settings.\(ProcessInfo.processInfo.processIdentifier)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        precondition(BuildAIProviderSettings.provider(in: defaults) == .openAI)
        BuildAIProviderSettings.saveProvider(.azureOpenAI, in: defaults)
        BuildAIProviderSettings.saveAzureConfiguration(configuration, in: defaults)
        precondition(BuildAIProviderSettings.provider(in: defaults) == .azureOpenAI)
        let storedConfiguration = try BuildAIProviderSettings.azureConfiguration(in: defaults)
        precondition(storedConfiguration == configuration)

        for endpoint in [
            "http://resource.openai.azure.com",
            "https://attacker.example",
            "https://resource.openai.azure.com:444",
            "https://resource.openai.azure.com/openai/v1?redirect=1",
            "https://resource.openai.azure.com/other",
            "https://key@resource.openai.azure.com"
        ] {
            do {
                _ = try AzureOpenAIConfiguration(endpoint: endpoint, deployment: "model")
                preconditionFailure("Unsafe Azure endpoint accepted: \(endpoint)")
            } catch AzureOpenAIConfiguration.ValidationError.invalidEndpoint {
                continue
            }
        }

        do {
            _ = try AzureOpenAIConfiguration(
                endpoint: "https://resource.openai.azure.com",
                deployment: "bad deployment/name"
            )
            preconditionFailure("Unsafe deployment name accepted")
        } catch AzureOpenAIConfiguration.ValidationError.invalidDeployment {
            // Expected.
        }
        print("Azure OpenAI configuration checks passed")
    }
}
