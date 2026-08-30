import Foundation

@main
enum DaytonaBridgeProcessCheck {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("pesu-daytona-bridge-\(UUID().uuidString)", isDirectory: true)
        let build = root.appendingPathComponent("build", isDirectory: true)
        let app = build.appendingPathComponent("Pēsu.app", isDirectory: true)
        let website = root.appendingPathComponent("website", isDirectory: true)
        try manager.createDirectory(at: app, withIntermediateDirectories: true)
        try manager.createDirectory(at: website, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: website.appendingPathComponent("package.json"))
        defer { try? manager.removeItem(at: root) }

        let resolved = DaytonaBridgeProcess.developmentBridgeDirectory(
            bundleURL: app,
            environment: [:],
            currentDirectory: manager.temporaryDirectory
        )
        precondition(resolved?.standardizedFileURL == website.standardizedFileURL)

        let override = DaytonaBridgeProcess.developmentBridgeDirectory(
            bundleURL: URL(fileURLWithPath: "/Applications/Pēsu.app"),
            environment: ["PESU_DAYTONA_BRIDGE_DIR": website.path],
            currentDirectory: manager.temporaryDirectory
        )
        precondition(override?.standardizedFileURL == website.standardizedFileURL)
        let environment = DaytonaBridgeProcess.bridgeEnvironment(parent: [
            "PATH": "/usr/bin",
            "OPENAI_API_KEY": "must-not-leak",
            "DAYTONA_API_KEY": "must-not-leak",
            "DAYTONA_OTEL_ENABLED": "true",
            "OTEL_EXPORTER_OTLP_HEADERS": "must-not-leak"
        ])
        precondition(environment["OPENAI_API_KEY"] == nil)
        precondition(environment["DAYTONA_API_KEY"] == nil)
        precondition(environment["DAYTONA_OTEL_ENABLED"] == nil)
        precondition(environment["OTEL_EXPORTER_OTLP_HEADERS"] == nil)
        let localPort = try DaytonaBridgeProcess.availableLocalPort()
        precondition(localPort > 0)
        print("Daytona bridge location checks passed")
    }
}
