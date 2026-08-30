import Foundation

enum AzureOpenAIConnectionResult: Equatable, Sendable {
    case working
    case invalidAPIKey
    case accessDenied
    case endpointOrDeploymentNotFound
    case rateOrCapacityLimited
    case responsesUnsupported
    case serviceUnavailable
    case unexpectedResponse
    case networkUnavailable
    case keyUnavailable

    var message: String {
        switch self {
        case .working:
            "Connected · endpoint, key, and deployment are working"
        case .invalidAPIKey:
            "Check failed · Azure rejected the API key"
        case .accessDenied:
            "Check failed · Azure denied access; check firewall and permissions"
        case .endpointOrDeploymentNotFound:
            "Check failed · endpoint or deployment was not found"
        case .rateOrCapacityLimited:
            "Azure responded, but the deployment is rate or capacity limited · try again shortly"
        case .responsesUnsupported:
            "Check failed · this deployment did not accept the Responses API request"
        case .serviceUnavailable:
            "Azure is temporarily unavailable · try again shortly"
        case .unexpectedResponse:
            "Check failed · Azure returned an unexpected response"
        case .networkUnavailable:
            "Check failed · this Mac could not reach the Azure endpoint"
        case .keyUnavailable:
            "Check failed · the saved Azure key is unavailable in Keychain"
        }
    }

    var isWorking: Bool { self == .working }
}

private final class NoRedirectURLSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

struct AzureOpenAIConnectionChecker: Sendable {
    private let session: URLSession
    private let credentialStore: APIKeyCredentialStore

    init(
        session: URLSession? = nil,
        credentialStore: APIKeyCredentialStore = APIKeyCredentialStore(
            service: APIKeyCredentialStore.azureOpenAIService
        )
    ) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            self.session = URLSession(
                configuration: configuration,
                delegate: NoRedirectURLSessionDelegate(),
                delegateQueue: nil
            )
        }
        self.credentialStore = credentialStore
    }

    func check(_ configuration: AzureOpenAIConfiguration) async -> AzureOpenAIConnectionResult {
        let apiKey: String
        do {
            guard let storedKey = try credentialStore.readAPIKey(), !storedKey.isEmpty else {
                return .keyUnavailable
            }
            apiKey = storedKey
        } catch {
            return .keyUnavailable
        }

        do {
            let request = try Self.makeRequest(configuration: configuration, apiKey: apiKey)
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unexpectedResponse }
            return Self.classify(statusCode: http.statusCode)
        } catch {
            return .networkUnavailable
        }
    }

    static func makeRequest(
        configuration: AzureOpenAIConfiguration,
        apiKey: String
    ) throws -> URLRequest {
        guard let url = URL(string: configuration.endpoint + "/responses") else {
            throw AzureOpenAIConfiguration.ValidationError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": configuration.deployment,
            "store": false,
            "input": "Reply with OK.",
            "max_output_tokens": 16
        ])
        return request
    }

    static func classify(statusCode: Int) -> AzureOpenAIConnectionResult {
        switch statusCode {
        case 200..<300: .working
        case 401: .invalidAPIKey
        case 403: .accessDenied
        case 404: .endpointOrDeploymentNotFound
        case 429: .rateOrCapacityLimited
        case 400: .responsesUnsupported
        case 500..<600: .serviceUnavailable
        default: .unexpectedResponse
        }
    }
}
