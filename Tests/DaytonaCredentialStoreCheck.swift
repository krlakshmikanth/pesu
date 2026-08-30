import Foundation

@main
enum DaytonaCredentialStoreCheck {
    static func main() throws {
        let service = "com.lattelabs.pesu.tests.daytona.\(ProcessInfo.processInfo.processIdentifier)"
        let store = DaytonaCredentialStore(service: service, account: "api-key")
        defer { try? store.deleteAPIKey() }

        precondition(!store.hasAPIKey)
        try store.saveAPIKey("  test-daytona-key  ")
        precondition(store.hasAPIKey)
        let initialKey = try store.readAPIKey()
        precondition(initialKey == "test-daytona-key")

        try store.saveAPIKey("replacement-key")
        let replacementKey = try store.readAPIKey()
        precondition(replacementKey == "replacement-key")

        do {
            try store.saveAPIKey("   ")
            preconditionFailure("An empty Daytona API key must be rejected")
        } catch DaytonaCredentialStore.StoreError.emptyAPIKey {
            // Expected.
        }

        do {
            try store.saveAPIKey("invalid\nkey")
            preconditionFailure("A key containing control characters must be rejected")
        } catch DaytonaCredentialStore.StoreError.invalidAPIKey {
            // Expected.
        }

        try store.deleteAPIKey()
        precondition(!store.hasAPIKey)
        let deletedKey = try store.readAPIKey()
        precondition(deletedKey == nil)
        print("Daytona Keychain credential checks passed")
    }
}
