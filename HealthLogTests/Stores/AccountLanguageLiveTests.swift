import Foundation
@testable import HealthLog
import Testing

/// Opt in against an isolated local service; ordinary unit runs never require a server.
@Suite("Account language live contract")
struct AccountLanguageLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["T02_SERVER_URL"] != nil))
    func nativeWriteMatchesAccountRead() async throws {
        let variables = ProcessInfo.processInfo.environment
        let address = try #require(variables["T02_SERVER_URL"])
        let url = try #require(URL(string: address))
        #expect(["localhost", "127.0.0.1"].contains(url.host))
        guard ["localhost", "127.0.0.1"].contains(url.host) else { return }
        let token = try #require(variables["T02_TOKEN"])
        let keychain = InMemoryKeychain()
        try keychain.setString(token, forKey: KeychainKey.authToken)
        let environment = AppEnvironment(baseURL: url, bundleID: "dev.healthlog.test", appVersion: "test", buildNumber: "0")
        let api = APIClient(environment: environment, keychain: keychain)
        let repository = SettingsRepository(api: api)
        let previous = try await repository.authMeServerPrefs()
        #expect(try await repository.setAccountLanguage(.simplifiedChinese) == .simplifiedChinese)
        #expect(try await repository.accountLanguage() == .simplifiedChinese)
        // The same endpoint Web uses after login must see the native write.
        let account = try await api.send(APIRequest<AuthMeServerPrefs>(
            method: .get, path: "/api/auth/me", maxRetries: 0, failFast: true
        ))
        #expect(account.locale == "zh-CN")
        #expect(account.unitPreference == previous.unitPreference)
        #expect(account.glucoseUnit == previous.glucoseUnit)
        #expect(account.timezone == previous.timezone)
    }
}
