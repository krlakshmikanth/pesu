import Foundation
import Security

struct APIKeyCredentialStore: Sendable {
    static let daytonaService = "com.lattelabs.pesu.daytona"
    static let openAIService = "com.lattelabs.pesu.openai"
    static let account = "api-key"

    enum StoreError: LocalizedError, Equatable {
        case emptyAPIKey
        case invalidAPIKey
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .emptyAPIKey:
                return "Enter an API key."
            case .invalidAPIKey:
                return "The API key contains invalid characters."
            case let .keychain(status):
                let detail = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
                return "Could not update the key in macOS Keychain: \(detail)."
            }
        }
    }

    let service: String
    let account: String

    init(service: String, account: String = Self.account) {
        self.service = service
        self.account = account
    }

    var hasAPIKey: Bool {
        (try? containsAPIKey()) == true
    }

    func containsAPIKey() throws -> Bool {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        return true
    }

    func readAPIKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw StoreError.keychain(status)
        }
        return String(data: data, encoding: .utf8)
    }

    func saveAPIKey(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw StoreError.emptyAPIKey }
        guard key.utf8.count <= 4_096,
              key.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw StoreError.invalidAPIKey
        }
        let data = Data(key.utf8)

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw StoreError.keychain(updateStatus)
        }

        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw StoreError.keychain(addStatus)
        }
    }

    func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
