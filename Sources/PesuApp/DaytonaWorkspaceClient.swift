import Foundation

@MainActor
final class DaytonaWorkspaceClient {
    enum ClientError: LocalizedError {
        case invalidBridgeURL
        case missingAPIKey
        case unexpectedResponse
        case requestFailed(status: Int, message: String)
        case remoteFailure(String)
        case endedWithoutPreview

        var errorDescription: String? {
            switch self {
            case .invalidBridgeURL:
                return "The Pēsu Daytona bridge URL is invalid."
            case .missingAPIKey:
                return "Add your Daytona API key in Pēsu Settings and try again."
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
    private let endpoint: URL?
    private let credentialStore: DaytonaCredentialStore

    init(
        session: URLSession = .shared,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        credentialStore: DaytonaCredentialStore = DaytonaCredentialStore()
    ) {
        self.session = session
        self.credentialStore = credentialStore
        let configured = environment["PESU_DAYTONA_BRIDGE_URL"]
            ?? "http://127.0.0.1:3000/api/daytona/workspaces"
        if let url = URL(string: configured),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            endpoint = url
        } else {
            endpoint = nil
        }
    }

    func createWorkspace(
        context: DaytonaWorkspaceContext,
        onEvent: (DaytonaWorkspaceEvent) -> Void
    ) async throws -> URL {
        guard let endpoint else { throw ClientError.invalidBridgeURL }
        guard let apiKey = try credentialStore.readAPIKey(), !apiKey.isEmpty else {
            throw ClientError.missingAPIKey
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
                message: Self.bridgeErrorMessage(from: message)
            )
        }

        for try await line in bytes.lines {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let event = try DaytonaWorkspaceEvent.decode(line: line)
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
            return body
        }
        return response.error
    }
}
