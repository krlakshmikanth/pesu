import Foundation

enum BuildAIProvider: String, CaseIterable, Equatable, Sendable {
    case openAI = "openai"
    case azureOpenAI = "azure-openai"

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .azureOpenAI: "Azure OpenAI"
        }
    }
}

struct AzureOpenAIConfiguration: Equatable, Sendable {
    enum ValidationError: LocalizedError, Equatable {
        case invalidEndpoint
        case invalidDeployment

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                "Enter an HTTPS Azure OpenAI resource endpoint such as https://my-resource.openai.azure.com."
            case .invalidDeployment:
                "Enter the Azure deployment name. Use only letters, numbers, periods, underscores, and hyphens."
            }
        }
    }

    let endpoint: String
    let deployment: String

    init(endpoint: String, deployment: String) throws {
        let rawEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawDeployment = deployment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rawEndpoint.utf8.count <= 512,
              let components = URLComponents(string: rawEndpoint),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil,
              let host = components.host?.lowercased(),
              host.hasSuffix(".openai.azure.com"),
              host != "openai.azure.com",
              components.path.isEmpty || components.path == "/" || components.path == "/openai/v1" || components.path == "/openai/v1/" else {
            throw ValidationError.invalidEndpoint
        }
        guard !rawDeployment.isEmpty,
              rawDeployment.utf8.count <= 128,
              rawDeployment.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            throw ValidationError.invalidDeployment
        }
        self.endpoint = "https://\(host)/openai/v1"
        self.deployment = rawDeployment
    }
}

enum BuildAIProviderSelection: Equatable, Sendable {
    case openAI
    case azureOpenAI(AzureOpenAIConfiguration)

    var provider: BuildAIProvider {
        switch self {
        case .openAI: .openAI
        case .azureOpenAI: .azureOpenAI
        }
    }

    var disclosure: String {
        switch self {
        case .openAI:
            "OpenAI · api.openai.com"
        case .azureOpenAI(let configuration):
            "Azure OpenAI · \(URL(string: configuration.endpoint)?.host ?? configuration.endpoint)"
        }
    }
}

struct BuildAIProviderSettings {
    static let providerKey = "pesu.build.aiProvider"
    static let azureEndpointKey = "pesu.build.azureOpenAI.endpoint"
    static let azureDeploymentKey = "pesu.build.azureOpenAI.deployment"

    static func provider(in defaults: UserDefaults = .standard) -> BuildAIProvider {
        defaults.string(forKey: providerKey).flatMap(BuildAIProvider.init(rawValue:)) ?? .openAI
    }

    static func azureConfiguration(in defaults: UserDefaults = .standard) throws -> AzureOpenAIConfiguration {
        try AzureOpenAIConfiguration(
            endpoint: defaults.string(forKey: azureEndpointKey) ?? "",
            deployment: defaults.string(forKey: azureDeploymentKey) ?? ""
        )
    }

    static func saveProvider(_ provider: BuildAIProvider, in defaults: UserDefaults = .standard) {
        defaults.set(provider.rawValue, forKey: providerKey)
    }

    static func saveAzureConfiguration(
        _ configuration: AzureOpenAIConfiguration,
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(configuration.endpoint, forKey: azureEndpointKey)
        defaults.set(configuration.deployment, forKey: azureDeploymentKey)
    }
}
