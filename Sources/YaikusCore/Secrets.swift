import Foundation
import Security

/// API keys in the macOS Keychain (never in files).
public enum Secrets {
    public static let service = "com.yaikus.studio"
    public enum Name: String { case agentKey = "agent_api_key", voiceKey = "voice_api_key", pexelsKey = "pexels_key" }

    public static func get(_ name: Name) -> String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: name.rawValue, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return "" }
        return String(data: d, encoding: .utf8) ?? ""
    }

    @discardableResult
    public static func set(_ name: Name, _ value: String) -> Bool {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: name.rawValue]
        SecItemDelete(base as CFDictionary)
        if value.isEmpty { return true }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
