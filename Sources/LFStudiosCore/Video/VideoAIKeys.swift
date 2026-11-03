import Foundation
import Security

// MARK: - The built-in assistant (1.20.0): providers and their keys

/// An AI provider the Assistant can talk to, with the user's own key.
enum VideoAIProvider: String, CaseIterable, Codable, Identifiable {
    case anthropic
    case openAI = "openai"
    case gemini

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anthropic: return "Anthropic (Claude)" // l10n-ignore: a company and product name
        case .openAI: return "OpenAI" // l10n-ignore: a company name
        case .gemini: return "Google Gemini" // l10n-ignore: a company and product name
        }
    }

    /// The short name, in the model picker.
    var shortTitle: String {
        switch self {
        case .anthropic: return "Claude" // l10n-ignore: a product name
        case .openAI: return "OpenAI" // l10n-ignore: a company name
        case .gemini: return "Gemini" // l10n-ignore: a product name
        }
    }

    /// Where to make a key.
    var keyPage: URL {
        switch self {
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")!
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")!
        }
    }

    /// What its keys start with (a hint in the empty field).
    var keyPrefix: String {
        switch self {
        case .anthropic: return "sk-ant-"
        case .openAI: return "sk-"
        case .gemini: return "AIza"
        }
    }
}

/// Where keys live: only in the macOS Keychain (`VideoAIKeychain`); tests
/// use a keychain of their own.
protocol VideoAIKeyStore: AnyObject {
    func key(for provider: VideoAIProvider) -> String?
    func setKey(_ key: String, for provider: VideoAIProvider) throws
    func removeKey(for provider: VideoAIProvider) throws
}

/// The app's own Keychain items, one per provider ("LF Studios AI –
/// Anthropic"…). Made by LF Studios, so LF Studios reads them without
/// asking each time (the same signature on every version keeps that).
final class VideoAIKeychain: VideoAIKeyStore {
    static let service = "LF Studios AI"
    /// A keychain file of its own (tests); nil: the login keychain.
    private let keychain: SecKeychain?

    init(keychain: SecKeychain? = nil) {
        self.keychain = keychain
    }

    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return L("The Keychain couldn't save the key: \(reason)")
        }
    }

    private func query(_ provider: VideoAIProvider) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: provider.rawValue,
        ]
        if let keychain {
            query[kSecUseKeychain as String] = keychain
            query[kSecMatchSearchList as String] = [keychain]
        }
        return query
    }

    func key(for provider: VideoAIProvider) -> String? {
        var query = query(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let data = found as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setKey(_ key: String, for provider: VideoAIProvider) throws {
        let data = Data(key.utf8)
        let update = SecItemUpdate(query(provider) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw Failure(status: update) }
        var add = query(provider)
        add.removeValue(forKey: kSecMatchSearchList as String)
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "\(Self.service) – \(provider.shortTitle)"
        add[kSecAttrDescription as String] = "API key"
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    func removeKey(for provider: VideoAIProvider) throws {
        let status = SecItemDelete(query(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}

/// Keys kept in memory only: what tests use, so a test never reads (or
/// asks macOS for) the app's real Keychain items.
final class VideoAIMemoryKeys: VideoAIKeyStore {
    private var keys: [VideoAIProvider: String] = [:]
    private let lock = NSLock()

    func key(for provider: VideoAIProvider) -> String? { lock.withLock { keys[provider] } }
    func setKey(_ key: String, for provider: VideoAIProvider) throws { lock.withLock { keys[provider] = key } }
    func removeKey(for provider: VideoAIProvider) throws { _ = lock.withLock { keys.removeValue(forKey: provider) } }
}

/// The keys in use: the Keychain in the app, a stand-in in tests.
enum VideoAIKeys {
    nonisolated(unsafe) static var store: VideoAIKeyStore = NSClassFromString("XCTestCase") == nil ? VideoAIKeychain() : VideoAIMemoryKeys()

    static func key(for provider: VideoAIProvider) -> String? {
        guard let key = store.key(for: provider)?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        return key
    }

    static func hasKey(_ provider: VideoAIProvider) -> Bool { key(for: provider) != nil }

    /// What Settings shows of a saved key: dots and its last 4 characters.
    static func masked(_ key: String) -> String {
        "••••" + String(key.suffix(4))
    }

    /// Text with every saved key (and anything shaped like one) taken out:
    /// for error messages, chat history and crash reports.
    static func scrubbed(_ text: String) -> String {
        var result = text
        for provider in VideoAIProvider.allCases {
            if let key = store.key(for: provider), key.count >= 8 {
                result = result.replacingOccurrences(of: key, with: "[key]")
            }
        }
        return scrubbedPatterns(result)
    }

    /// Anything shaped like an Anthropic, OpenAI or Google key.
    static func scrubbedPatterns(_ text: String) -> String {
        var result = text
        for pattern in [#"sk-ant-[A-Za-z0-9_\-]{8,}"#, #"sk-[A-Za-z0-9_\-]{16,}"#, #"AIza[A-Za-z0-9_\-]{20,}"#] {
            result = result.replacingOccurrences(of: pattern, with: "[key]", options: .regularExpression)
        }
        return result
    }
}
