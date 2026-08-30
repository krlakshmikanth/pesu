import Darwin
import Foundation

struct DaytonaBridgeConnection: Sendable {
    let endpoint: URL
    let token: String
}

@MainActor
final class DaytonaBridgeProcess {
    static let shared = DaytonaBridgeProcess()

    enum BridgeError: LocalizedError {
        case runtimeUnavailable
        case resourcesUnavailable
        case launchFailed(String)
        case didNotBecomeReady(String)

        var errorDescription: String? {
            switch self {
            case .runtimeUnavailable:
                return "Pēsu needs Node.js to run its local Daytona bridge. Install Node.js 20 or later and try again."
            case .resourcesUnavailable:
                return "The local Daytona bridge is missing from this Pēsu build. Rebuild the app and try again."
            case let .launchFailed(detail):
                return detail.isEmpty
                    ? "Pēsu could not start its local Daytona bridge."
                    : "Pēsu could not start its local Daytona bridge: \(detail)"
            case let .didNotBecomeReady(detail):
                return detail.isEmpty
                    ? "The local Daytona bridge did not become ready."
                    : "The local Daytona bridge did not become ready: \(detail)"
            }
        }
    }

    private var process: Process?
    private var endpoint: URL?
    private var bridgeToken: String?
    private var recentOutput = ""

    func ensureRunning() async throws -> DaytonaBridgeConnection {
        if let process, process.isRunning, let endpoint, let bridgeToken,
           await isReachable(endpoint: endpoint, token: bridgeToken) {
            return DaytonaBridgeConnection(endpoint: endpoint, token: bridgeToken)
        }
        if process?.isRunning == true { stop() }
        try start()

        for _ in 0..<80 {
            if let endpoint, let bridgeToken,
               await isReachable(endpoint: endpoint, token: bridgeToken) {
                return DaytonaBridgeConnection(endpoint: endpoint, token: bridgeToken)
            }
            if let process, !process.isRunning {
                throw BridgeError.launchFailed(cleanDetail(recentOutput))
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw BridgeError.didNotBecomeReady(cleanDetail(recentOutput))
    }

    func stop() {
        if let process, process.isRunning { process.terminate() }
        self.process = nil
        endpoint = nil
        bridgeToken = nil
    }

    private func start() throws {
        let port = try Self.availableLocalPort()
        let endpoint = URL(string: "http://127.0.0.1:\(port)/api/daytona/workspaces")!
        let launch = try resolveLaunch(port: port)
        let bridgeToken = UUID().uuidString
        let process = Process()
        process.executableURL = launch.executable
        process.arguments = launch.arguments
        process.currentDirectoryURL = launch.workingDirectory
        var environment = launch.environment
        environment["PESU_BRIDGE_TOKEN"] = bridgeToken
        process.environment = environment

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in self?.capture(text) }
        }
        process.terminationHandler = { _ in output.fileHandleForReading.readabilityHandler = nil }

        do {
            try process.run()
            self.process = process
            self.endpoint = endpoint
            self.bridgeToken = bridgeToken
        } catch {
            throw BridgeError.launchFailed(error.localizedDescription)
        }
    }

    private func resolveLaunch(port: UInt16) throws -> LaunchConfiguration {
        guard let node = Self.nodeExecutable() else { throw BridgeError.runtimeUnavailable }

        let bundled = Bundle.main.resourceURL?.appendingPathComponent("DaytonaBridge", isDirectory: true)
        if let bundled,
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("server.js").path) {
            var environment = Self.bridgeEnvironment()
            environment["HOSTNAME"] = "127.0.0.1"
            environment["PORT"] = String(port)
            environment["NODE_ENV"] = "production"
            return LaunchConfiguration(
                executable: node,
                arguments: ["server.js"],
                workingDirectory: bundled,
                environment: environment
            )
        }

        if let source = Self.developmentBridgeDirectory() {
            var environment = Self.bridgeEnvironment()
            environment["HOSTNAME"] = "127.0.0.1"
            environment["PORT"] = String(port)
            return LaunchConfiguration(
                executable: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["npm", "run", "dev"],
                workingDirectory: source,
                environment: environment
            )
        }
        throw BridgeError.resourcesUnavailable
    }

    private func isReachable(endpoint: URL, token: String) async -> Bool {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "X-Pesu-Bridge-Token")
        request.timeoutInterval = 0.5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            let value = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return value?["service"] as? String == "pesu-daytona-bridge"
        } catch {
            return false
        }
    }

    private func capture(_ text: String) {
        recentOutput = String((recentOutput + text).suffix(4_000))
    }

    private func cleanDetail(_ text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .suffix(2)
            .joined(separator: " ")
            .redacting(ProcessInfo.processInfo.environment["OPENAI_API_KEY"])
            .redacting(ProcessInfo.processInfo.environment["DAYTONA_API_KEY"])
            .redacting(bridgeToken)
    }

    nonisolated static func developmentBridgeDirectory(
        bundleURL: URL = Bundle.main.bundleURL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> URL? {
        var candidates: [URL] = []
        if let configured = environment["PESU_DAYTONA_BRIDGE_DIR"], !configured.isEmpty {
            candidates.append(URL(fileURLWithPath: configured, isDirectory: true))
        }
        if bundleURL.pathExtension == "app" {
            candidates.append(
                bundleURL.deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent("website", isDirectory: true)
            )
        }
        candidates.append(currentDirectory.appendingPathComponent("website", isDirectory: true))
        return candidates.first { candidate in
            FileManager.default.fileExists(atPath: candidate.appendingPathComponent("package.json").path)
        }
    }

    nonisolated static func availableLocalPort() throws -> UInt16 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw BridgeError.launchFailed("Pēsu could not reserve a local bridge port.")
        }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            throw BridgeError.launchFailed("Pēsu could not reserve a local bridge port.")
        }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let resolved = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard resolved == 0 else {
            throw BridgeError.launchFailed("Pēsu could not resolve its local bridge port.")
        }
        return UInt16(bigEndian: address.sin_port)
    }

    private static func nodeExecutable() -> URL? {
        ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    nonisolated private static func runtimePath(existing: String?) -> String {
        ["/opt/homebrew/bin", "/usr/local/bin", existing]
            .compactMap { $0 }
            .joined(separator: ":")
    }

    nonisolated static func bridgeEnvironment(
        parent: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        return [
            "PATH": runtimePath(existing: parent["PATH"]),
            "HOME": NSHomeDirectory(),
            "TMPDIR": NSTemporaryDirectory(),
            "LANG": parent["LANG"] ?? "en_US.UTF-8"
        ]
    }
}

private extension String {
    func redacting(_ secret: String?) -> String {
        guard let secret, !secret.isEmpty else { return self }
        return replacingOccurrences(of: secret, with: "[redacted]")
    }
}

private struct LaunchConfiguration {
    let executable: URL
    let arguments: [String]
    let workingDirectory: URL
    let environment: [String: String]
}
