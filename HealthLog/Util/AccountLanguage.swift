import CryptoKit
import Foundation
import Observation
import os

public enum AccountLanguage: String, CaseIterable, Codable, Sendable {
    case german = "de"
    case english = "en"
    case french = "fr"
    case spanish = "es"
    case italian = "it"
    case polish = "pl"
    case korean = "ko"
    case dutch = "nl"
    case brazilianPortuguese = "pt-BR"
    case simplifiedChinese = "zh-CN"

    public init?(tag: String) {
        let normalized = tag.replacingOccurrences(of: "_", with: "-").lowercased()
        if normalized == "zh-hans" {
            self = .simplifiedChinese
        } else if let language = Self.allCases.first(where: { $0.rawValue.lowercased() == normalized }) {
            self = language
        } else {
            return nil
        }
    }

    public var locale: Locale {
        Locale(identifier: self == .simplifiedChinese ? "zh-Hans" : rawValue)
    }

    public var nativeName: String {
        switch self {
        case .german: "Deutsch"
        case .english: "English"
        case .french: "Français"
        case .spanish: "Español"
        case .italian: "Italiano"
        case .polish: "Polski"
        case .korean: "한국어"
        case .dutch: "Nederlands"
        case .brazilianPortuguese: "Português (Brasil)"
        case .simplifiedChinese: "简体中文"
        }
    }
}

/// One observable locale for SwiftUI and Foundation readers, including off-main-actor work.
public final class AppLocale: Observable, Sendable {
    public static let shared = AppLocale()
    private let registrar = ObservationRegistrar()
    private let language = OSAllocatedUnfairLock<AccountLanguage?>(initialState: nil)

    public init() {}

    public static func string(_ value: LocalizedStringResource, locale: Locale? = nil) -> String {
        String(localized: shared.resource(value, locale: locale))
    }

    public var current: Locale {
        registrar.access(self, keyPath: \.current)
        return language.withLock { $0?.locale ?? .autoupdatingCurrent }
    }

    public var serverCode: String {
        registrar.access(self, keyPath: \.current)
        if let value = language.withLock({ $0 }) { return value.rawValue }
        return Bundle.main.preferredLocalizations.first.flatMap { AccountLanguage(tag: $0)?.rawValue } ?? "en"
    }

    public func resource(_ value: String.LocalizationValue) -> LocalizedStringResource {
        resource(LocalizedStringResource(value))
    }

    public func resource(_ value: LocalizedStringResource, locale: Locale? = nil) -> LocalizedStringResource {
        var resolved = value
        resolved.locale = locale ?? current
        // An incomplete catalog must fall back to the English sentence, not expose its key.
        if String(localized: resolved) == resolved.key {
            resolved.locale = Locale(identifier: "en")
        }
        return resolved
    }

    public func apply(_ value: AccountLanguage?) {
        registrar.withMutation(of: self, keyPath: \.current) {
            language.withLock { $0 = value }
        }
    }
}

public struct AccountLanguageCache {
    private let defaults: UserDefaults
    private static let key = "hl.account.language"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load(ownerID: String, server: String) -> AccountLanguage? {
        guard let record = defaults.dictionary(forKey: Self.key) as? [String: String],
              record["owner"] == ownerID,
              record["server"] == serverFingerprint(server),
              let language = record["language"] else { return nil }
        return AccountLanguage(tag: language)
    }

    public func save(_ language: AccountLanguage, ownerID: String, server: String) {
        defaults.set(["owner": ownerID, "server": serverFingerprint(server), "language": language.rawValue], forKey: Self.key)
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }

    /// The private self-hosted address belongs in Keychain, not in the preference cache.
    private func serverFingerprint(_ server: String) -> String {
        SHA256.hash(data: Data(server.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
