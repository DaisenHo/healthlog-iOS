import Foundation

public extension SettingsRepository {
    func accountLanguage(authorization: String? = nil) async throws -> AccountLanguage {
        let request = APIRequest<AccountLanguagePayload>(
            method: .get,
            path: "/api/auth/me/locale",
            extraHeaders: authorization.map { ["Authorization": $0] } ?? [:],
            maxRetries: 0,
            failFast: true,
            allowsAuthenticationRecovery: false
        )
        return try await api.send(request).locale
    }

    func setAccountLanguage(_ language: AccountLanguage, authorization: String? = nil) async throws -> AccountLanguage {
        let request = try APIRequest<AccountLanguagePayload>(
            method: .put,
            path: "/api/auth/me/locale",
            body: JSONEncoder.hlDefault.encode(AccountLanguagePayload(locale: language)),
            extraHeaders: authorization.map { ["Authorization": $0] } ?? [:],
            maxRetries: 0,
            failFast: true,
            allowsAuthenticationRecovery: false
        )
        return try await api.send(request).locale
    }
}

public struct AccountLanguagePayload: Codable, Sendable {
    public let locale: AccountLanguage

    public init(locale: AccountLanguage) {
        self.locale = locale
    }
}
