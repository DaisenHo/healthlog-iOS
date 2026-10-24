import Foundation
@testable import HealthLog
import Testing

@MainActor
@Suite("Account language synchronization", .serialized)
struct SettingsStoreLanguageTests {
    private struct Fixture {
        let store: SettingsStore
        let registry: AuthenticatedSessionLeaseRegistry
        let keychain: InMemoryKeychain
    }

    private func makeFixture(api: StubAPIClient, defaults: UserDefaults) throws -> Fixture {
        let keychain = InMemoryKeychain()
        try keychain.setString("language-owner", forKey: KeychainKey.userID)
        try keychain.setString("language-test-token", forKey: KeychainKey.authToken)
        try keychain.setString("https://language.example.test", forKey: KeychainKey.serverURL)
        let registry = AuthenticatedSessionLeaseRegistry()
        registry.activate(ownerID: "language-owner")
        let store = SettingsStore(
            repo: SettingsRepository(api: api),
            defaults: defaults,
            authenticatedSessionRegistry: registry,
            userIDProvider: { keychain.getString(forKey: KeychainKey.userID) },
            accountLanguageKeychain: keychain
        )
        return Fixture(store: store, registry: registry, keychain: keychain)
    }

    @Test("A failed save preserves the last account language")
    func failedSaveKeepsLanguage() async throws {
        let api = StubAPIClient()
        await api.setHandler { _ in throw HLError.offline }
        let suite = "SettingsStoreLanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(repo: SettingsRepository(api: api), defaults: defaults)
        #expect(await store.setAccountLanguage(.simplifiedChinese) == false)
        #expect(store.accountLanguage == nil)
        #expect(store.accountLanguageNotice == .onlineRequired)
        #expect(store.isSavingAccountLanguage == false)
    }

    @Test("The acknowledged account choice survives a restart without changing units")
    func successfulSaveAndRestart() async throws {
        let api = StubAPIClient()
        await api.setHandler { value in
            let request = try #require(value as? APIRequest<AccountLanguagePayload>)
            #expect(request.method == .put)
            #expect(request.path == "/api/auth/me/locale")
            #expect(request.maxRetries == 0)
            let body = try JSONDecoder().decode(AccountLanguagePayload.self, from: #require(request.body))
            #expect(body.locale == .simplifiedChinese)
            return AccountLanguagePayload(locale: .simplifiedChinese)
        }
        let suite = "SettingsStoreLanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("imperial", forKey: HLUnitPreference.defaultsKey)
        let fixture = try makeFixture(api: api, defaults: defaults)
        #expect(await fixture.store.setAccountLanguage(.simplifiedChinese))
        #expect(fixture.store.accountLanguage == .simplifiedChinese)
        let restarted = try makeFixture(api: api, defaults: defaults)
        #expect(restarted.store.accountLanguage == .simplifiedChinese)
        #expect(restarted.store.unitPreference == .imperial)
        #expect(restarted.store.accountLanguageNotice == nil)
    }

    @Test("A denied write keeps the confirmed language and a later read adopts another device's change")
    func failedWriteAndReconnect() async throws {
        let api = StubAPIClient()
        await api.setHandler { value in
            let request = try #require(value as? APIRequest<AccountLanguagePayload>)
            if request.method == .get { return AccountLanguagePayload(locale: .english) }
            throw HLError.server(status: 403, code: nil, message: "Refused")
        }
        let suite = "SettingsStoreLanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = try makeFixture(api: api, defaults: defaults)
        await fixture.store.refreshAccountLanguage()
        #expect(fixture.store.accountLanguage == .english)
        #expect(await fixture.store.setAccountLanguage(.simplifiedChinese) == false)
        #expect(fixture.store.accountLanguage == .english)
        #expect(fixture.store.accountLanguageNotice == .saveFailed)
        await api.setHandler { _ in throw HLError.offline }
        #expect(await fixture.store.setAccountLanguage(.simplifiedChinese) == false)
        #expect(fixture.store.accountLanguageNotice == .onlineRequired)
        await api.setHandler { _ in AccountLanguagePayload(locale: .simplifiedChinese) }
        await fixture.store.refreshAccountLanguage()
        #expect(fixture.store.accountLanguage == .simplifiedChinese)
        #expect(fixture.store.accountLanguageNotice == nil)
    }

    @Test("A mismatched acknowledgement cannot report a successful save")
    func mismatchedAcknowledgement() async throws {
        let api = StubAPIClient()
        await api.setHandler { _ in AccountLanguagePayload(locale: .english) }
        let suite = "SettingsStoreLanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = try makeFixture(api: api, defaults: defaults)
        #expect(await fixture.store.setAccountLanguage(.simplifiedChinese) == false)
        #expect(fixture.store.accountLanguage == nil)
        #expect(fixture.store.accountLanguageNotice == .saveFailed)
    }

    @Test("A read started before an explicit save cannot restore the previous language")
    func oldReadCannotOverwriteSave() async throws {
        let api = StubAPIClient()
        let gate = Gate()
        await api.setHandler { value in
            let request = try #require(value as? APIRequest<AccountLanguagePayload>)
            if request.method == .get {
                await gate.enter()
                return AccountLanguagePayload(locale: .english)
            }
            return AccountLanguagePayload(locale: .simplifiedChinese)
        }
        let suite = "SettingsStoreLanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = try makeFixture(api: api, defaults: defaults)
        let read = Task { await fixture.store.refreshAccountLanguage() }
        await gate.waitUntilEntered()
        #expect(await fixture.store.setAccountLanguage(.simplifiedChinese))
        await gate.open()
        await read.value
        #expect(fixture.store.accountLanguage == .simplifiedChinese)
    }

    @Test("A write from a signed-out account cannot overwrite the next account's language")
    func oldWriteCannotCrossAccounts() async throws {
        let api = StubAPIClient()
        let gate = Gate()
        await api.setHandler { value in
            let request = try #require(value as? APIRequest<AccountLanguagePayload>)
            if request.method == .get { return AccountLanguagePayload(locale: .english) }
            #expect(request.extraHeaders["Authorization"] == "Bearer language-test-token")
            await gate.enter()
            return AccountLanguagePayload(locale: .simplifiedChinese)
        }
        let suite = "SettingsStoreLanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = try makeFixture(api: api, defaults: defaults)
        let write = Task { await fixture.store.setAccountLanguage(.simplifiedChinese) }
        await gate.waitUntilEntered()
        #expect(fixture.store.isSavingAccountLanguage)
        fixture.registry.invalidate()
        fixture.store.clearOnLogout()
        try fixture.keychain.setString("next-language-owner", forKey: KeychainKey.userID)
        fixture.registry.activate(ownerID: "next-language-owner")
        await fixture.store.refreshAccountLanguage()
        await gate.open()
        #expect(await write.value == false)
        #expect(fixture.store.accountLanguage == .english)
        #expect(fixture.store.isSavingAccountLanguage == false)
    }

    private actor Gate {
        private var entered: CheckedContinuation<Void, Never>?
        private var released: CheckedContinuation<Void, Never>?
        private var hasEntered = false
        private var isReleased = false

        func waitUntilEntered() async {
            if hasEntered { return }
            await withCheckedContinuation { entered = $0 }
        }

        func enter() async {
            hasEntered = true
            entered?.resume()
            entered = nil
            if isReleased { return }
            await withCheckedContinuation { released = $0 }
        }

        func open() {
            isReleased = true
            released?.resume()
            released = nil
        }
    }
}
