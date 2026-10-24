import Foundation

public enum AccountLanguageNotice: Sendable, Equatable {
    case onlineRequired
    case saveFailed
}

public extension SettingsStore {
    func restoreCachedAccountLanguage() {
        guard let keychain = accountLanguageKeychain,
              keychain.getString(forKey: KeychainKey.authToken) != nil,
              let owner = keychain.getString(forKey: KeychainKey.userID),
              let server = keychain.getString(forKey: KeychainKey.serverURL) else { return }
        accountLanguage = AccountLanguageCache(defaults: defaults).load(ownerID: owner, server: server)
    }

    internal func adoptAccountLanguage(_ value: AccountLanguage, ownerID: String) {
        accountLanguage = value
        if let server = accountLanguageKeychain?.getString(forKey: KeychainKey.serverURL) {
            AccountLanguageCache(defaults: defaults).save(value, ownerID: ownerID, server: server)
        }
    }

    private func languageAuthorization(for lease: AuthenticatedSessionLease) throws -> String? {
        guard let keychain = accountLanguageKeychain else { return nil }
        guard keychain.getString(forKey: KeychainKey.userID) == lease.ownerID,
              let token = keychain.getString(forKey: KeychainKey.authToken) else { throw HLError.unauthorized }
        return "Bearer \(token)"
    }

    func refreshAccountLanguage() async {
        guard !isSavingAccountLanguage, backend?.isReachable != false,
              let lease = captureAuthenticatedSessionLease() else { return }
        accountLanguageRevision &+= 1
        let revision = accountLanguageRevision
        do {
            let authorization = try languageAuthorization(for: lease)
            try lease.requireCurrent()
            let language = try await repo.accountLanguage(authorization: authorization)
            try lease.requireCurrent()
            guard revision == accountLanguageRevision else { return }
            adoptAccountLanguage(language, ownerID: lease.ownerID)
            accountLanguageNotice = nil
        } catch {
            // Offline reads keep the last confirmed account language.
        }
    }

    @discardableResult
    func setAccountLanguage(_ value: AccountLanguage) async -> Bool {
        guard !isSavingAccountLanguage,
              let lease = captureAuthenticatedSessionLease() else { return false }
        guard backend?.isReachable != false else {
            accountLanguageNotice = .onlineRequired
            return false
        }
        accountLanguageRevision &+= 1
        let revision = accountLanguageRevision
        isSavingAccountLanguage = true
        accountLanguageNotice = nil
        defer {
            if revision == accountLanguageRevision { isSavingAccountLanguage = false }
        }
        do {
            let authorization = try languageAuthorization(for: lease)
            try lease.requireCurrent()
            let saved = try await repo.setAccountLanguage(value, authorization: authorization)
            try lease.requireCurrent()
            guard revision == accountLanguageRevision else { return false }
            guard saved == value else { throw HLError.decoding("Account language acknowledgement did not match") }
            adoptAccountLanguage(saved, ownerID: lease.ownerID)
            return true
        } catch {
            guard authenticatedEffectIsCurrent(lease), revision == accountLanguageRevision else { return false }
            if let error = error as? HLError, case .offline = error {
                accountLanguageNotice = .onlineRequired
            } else {
                accountLanguageNotice = .saveFailed
            }
            return false
        }
    }

    internal func clearAccountLanguage() {
        accountLanguageRevision &+= 1
        accountLanguage = nil
        isSavingAccountLanguage = false
        accountLanguageNotice = nil
        AccountLanguageCache(defaults: defaults).clear()
    }
}
