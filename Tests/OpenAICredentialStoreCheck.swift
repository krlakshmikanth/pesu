import Foundation

@main
enum OpenAICredentialStoreCheck {
    static func main() throws {
        let service = "com.lattelabs.pesu.tests.openai.\(ProcessInfo.processInfo.processIdentifier)"
        let store = APIKeyCredentialStore(service: service, account: "api-key")
        let peerStore = APIKeyCredentialStore(service: service + ".daytona", account: "api-key")
        defer {
            try? store.deleteAPIKey()
            try? peerStore.deleteAPIKey()
        }

        precondition(!store.hasAPIKey)
        try store.saveAPIKey("  test-openai-key  ")
        precondition(store.hasAPIKey)
        let initialKey = try store.readAPIKey()
        precondition(initialKey == "test-openai-key")

        try store.saveAPIKey("replacement-key")
        try peerStore.saveAPIKey("separate-daytona-key")
        let replacementKey = try store.readAPIKey()
        let peerKey = try peerStore.readAPIKey()
        precondition(replacementKey == "replacement-key")
        precondition(peerKey == "separate-daytona-key")

        do {
            try store.saveAPIKey("   ")
            preconditionFailure("An empty OpenAI API key must be rejected")
        } catch APIKeyCredentialStore.StoreError.emptyAPIKey {
            // Expected.
        }

        do {
            try store.saveAPIKey("invalid\nkey")
            preconditionFailure("A key containing control characters must be rejected")
        } catch APIKeyCredentialStore.StoreError.invalidAPIKey {
            // Expected.
        }

        do {
            try store.saveAPIKey(String(repeating: "k", count: 4_097))
            preconditionFailure("An oversized API key must be rejected")
        } catch APIKeyCredentialStore.StoreError.invalidAPIKey {
            // Expected.
        }

        try store.deleteAPIKey()
        precondition(!store.hasAPIKey)
        let deletedKey = try store.readAPIKey()
        let preservedPeerKey = try peerStore.readAPIKey()
        precondition(deletedKey == nil)
        precondition(preservedPeerKey == "separate-daytona-key")
        print("OpenAI Keychain credential checks passed")
    }
}
