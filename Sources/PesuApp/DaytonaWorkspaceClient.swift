import Foundation

@MainActor
final class DaytonaWorkspaceClient {
    enum ClientError: LocalizedError {
        case missingAPIKey
        case missingOpenAIAPIKey
        case missingAzureOpenAIAPIKey
        case invalidAzureOpenAIConfiguration
        case unexpectedResponse
        case requestFailed(status: Int, message: String)
        case remoteFailure(String)
        case endedWithoutPreview

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Add your Daytona API key in Pēsu Settings and try again."
            case .missingOpenAIAPIKey:
                return "Add your OpenAI API key in Pēsu Settings and try again."
            case .missingAzureOpenAIAPIKey:
                return "Add your Azure OpenAI API key in Pēsu Settings and try again."
            case .invalidAzureOpenAIConfiguration:
                return "Add a valid Azure OpenAI endpoint and deployment in Pēsu Settings and try again."
            case .unexpectedResponse:
                return "The Pēsu Daytona bridge returned an unexpected response."
            case let .requestFailed(status, message):
                return message.isEmpty ? "The Pēsu Daytona bridge failed (HTTP \(status))." : message
            case let .remoteFailure(message):
                return message
            case .endedWithoutPreview:
                return "The workspace finished without a preview URL."
            }
        }
    }

    private let session: URLSession
    private let endpoint = URL(string: "http://127.0.0.1:3000/api/daytona/workspaces")!
    private let daytonaCredentialStore: APIKeyCredentialStore
    private let openAICredentialStore: APIKeyCredentialStore
    private let azureOpenAICredentialStore: APIKeyCredentialStore
    private let providerSelection: BuildAIProviderSelection

    init(
        providerSelection: BuildAIProviderSelection,
        session: URLSession = .shared,
        daytonaCredentialStore: APIKeyCredentialStore = APIKeyCredentialStore(
            service: APIKeyCredentialStore.daytonaService
        ),
        openAICredentialStore: APIKeyCredentialStore = APIKeyCredentialStore(
            service: APIKeyCredentialStore.openAIService
        ),
        azureOpenAICredentialStore: APIKeyCredentialStore = APIKeyCredentialStore(
            service: APIKeyCredentialStore.azureOpenAIService
        )
    ) {
        self.providerSelection = providerSelection
        self.session = session
        self.daytonaCredentialStore = daytonaCredentialStore
        self.openAICredentialStore = openAICredentialStore
        self.azureOpenAICredentialStore = azureOpenAICredentialStore
    }

    func createWorkspace(
        context: DaytonaWorkspaceContext,
        onEvent: (DaytonaWorkspaceEvent) -> Void
    ) async throws -> URL {
        guard let daytonaAPIKey = try daytonaCredentialStore.readAPIKey(), !daytonaAPIKey.isEmpty else {
            throw ClientError.missingAPIKey
        }
        let provider = providerSelection.provider
        let providerKey: String
        var azureConfiguration: AzureOpenAIConfiguration?
        switch provider {
        case .openAI:
            guard let key = try openAICredentialStore.readAPIKey(), !key.isEmpty else {
                throw ClientError.missingOpenAIAPIKey
            }
            providerKey = key
        case .azureOpenAI:
            guard let key = try azureOpenAICredentialStore.readAPIKey(), !key.isEmpty else {
                throw ClientError.missingAzureOpenAIAPIKey
            }
            guard case .azureOpenAI(let configuration) = providerSelection else {
                throw ClientError.invalidAzureOpenAIConfiguration
            }
            providerKey = key
            azureConfiguration = configuration
        }
        let bridgeToken = try await DaytonaBridgeProcess.shared.ensureRunning()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(daytonaAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue(provider.rawValue, forHTTPHeaderField: "X-Pesu-AI-Provider")
        request.setValue("Bearer \(providerKey)", forHTTPHeaderField: "X-Pesu-AI-Authorization")
        if let azureConfiguration {
            request.setValue(azureConfiguration.endpoint, forHTTPHeaderField: "X-Pesu-Azure-Endpoint")
            request.setValue(azureConfiguration.deployment, forHTTPHeaderField: "X-Pesu-Azure-Deployment")
        }
        request.setValue(bridgeToken, forHTTPHeaderField: "X-Pesu-Bridge-Token")
        request.httpBody = try JSONEncoder().encode(context)
        request.timeoutInterval = 15 * 60

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.unexpectedResponse
        }

        if !(200..<300).contains(http.statusCode) {
            var message = ""
            for try await line in bytes.lines {
                message.append(line)
                if message.count >= 1_000 { break }
            }
            throw ClientError.requestFailed(
                status: http.statusCode,
                message: Self.redact(
                    Self.bridgeErrorMessage(from: message),
                    secrets: [daytonaAPIKey, providerKey]
                )
            )
        }

        for try await line in bytes.lines {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let decoded = try DaytonaWorkspaceEvent.decode(line: line)
            let event = DaytonaWorkspaceEvent(
                type: decoded.type,
                message: Self.redact(decoded.message, secrets: [daytonaAPIKey, providerKey]),
                sandboxId: decoded.sandboxId,
                previewURL: decoded.previewURL
            )
            onEvent(event)
            if event.type == .failed {
                throw ClientError.remoteFailure(event.message)
            }
            if event.type == .ready, let previewURL = event.previewURL {
                return previewURL
            }
        }
        throw ClientError.endedWithoutPreview
    }

    private static func bridgeErrorMessage(from body: String) -> String {
        struct ErrorResponse: Decodable { let error: String }
        guard let data = body.data(using: .utf8),
              let response = try? JSONDecoder().decode(ErrorResponse.self, from: data) else {
            return ""
        }
        return response.error
    }

    private static func redact(_ value: String, secrets: [String]) -> String {
        secrets.reduce(value) { redacted, secret in
            guard !secret.isEmpty else { return redacted }
            return redacted.replacingOccurrences(of: secret, with: "[redacted]")
        }
    }
}
