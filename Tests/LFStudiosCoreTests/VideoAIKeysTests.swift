import Security
import XCTest
@testable import LFStudiosCore

/// AI keys (1.20.0): kept only in the Keychain (here a throwaway keychain
/// file, never the login keychain), shown as dots and the last 4
/// characters, and scrubbed out of any text.
final class VideoAIKeysTests: XCTestCase {
    private var folder: URL!
    private var keychain: SecKeychain?

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-ai-keys-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let password = "test"
        let status = folder.appendingPathComponent("test.keychain-db").path.withCString { path in
            SecKeychainCreate(path, UInt32(password.utf8.count), password, false, nil, &keychain)
        }
        guard status == errSecSuccess, keychain != nil else { throw XCTSkip("A test keychain couldn't be made here (\(status))") }
    }

    override func tearDownWithError() throws {
        if let keychain { SecKeychainDelete(keychain) }
        try? FileManager.default.removeItem(at: folder)
    }

    func testTestsNeverUseTheLoginKeychain() {
        XCTAssertTrue(VideoAIKeys.store is VideoAIMemoryKeys, "a test process keeps keys in memory")
    }

    func testAKeyIsSavedReplacedAndRemovedInTheKeychain() throws {
        let store = VideoAIKeychain(keychain: keychain)
        XCTAssertNil(store.key(for: .anthropic))
        try store.setKey("sk-ant-test-0000-first", for: .anthropic)
        XCTAssertEqual(store.key(for: .anthropic), "sk-ant-test-0000-first")
        try store.setKey("sk-ant-test-0000-second", for: .anthropic)
        XCTAssertEqual(store.key(for: .anthropic), "sk-ant-test-0000-second", "saving again replaces it")
        XCTAssertNil(store.key(for: .openAI), "one item per provider")
        try store.setKey("sk-test-openai-000000000000", for: .openAI)

        // One item per provider, named for people looking in Keychain Access.
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: VideoAIKeychain.service,
                                    kSecMatchSearchList as String: [keychain!], kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var found: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &found), errSecSuccess)
        let labels = Set((found as? [[String: Any]] ?? []).compactMap { $0[kSecAttrLabel as String] as? String })
        XCTAssertEqual(labels, ["LF Studios AI – Claude", "LF Studios AI – OpenAI"])

        try store.removeKey(for: .anthropic)
        XCTAssertNil(store.key(for: .anthropic))
        XCTAssertNotNil(store.key(for: .openAI))
        XCTAssertNoThrow(try store.removeKey(for: .anthropic), "removing twice is fine")
        query.removeValue(forKey: kSecReturnAttributes as String)
    }

    func testOnlyTheLastFourCharactersShow() {
        XCTAssertEqual(VideoAIKeys.masked("sk-ant-api03-abcdefWXYZ"), "••••WXYZ")
    }

    func testKeysAreScrubbedFromText() throws {
        let saved = VideoAIKeys.store
        defer { VideoAIKeys.store = saved }
        let memory = VideoAIMemoryKeys()
        VideoAIKeys.store = memory
        try memory.setKey("custom-key-without-a-prefix-123", for: .gemini)
        let text = "Bad key custom-key-without-a-prefix-123; also sk-ant-api03-ABCDEFGHIJ and sk-proj-ABCDEFGHIJKLMNOPQRS and AIzaSyABCDEFGHIJKLMNOPQRSTUV."
        let scrubbed = VideoAIKeys.scrubbed(text)
        for secret in ["custom-key-without-a-prefix-123", "sk-ant-api03-ABCDEFGHIJ", "sk-proj-ABCDEFGHIJKLMNOPQRS", "AIzaSyABCDEFGHIJKLMNOPQRSTUV"] {
            XCTAssertFalse(scrubbed.contains(secret), secret)
        }
        XCTAssertTrue(CrashReportFile.redacted("sk-ant-api03-ABCDEFGHIJ crashed", home: "/nowhere", user: "x").contains("[key]"), "crash reports too")
    }
}
