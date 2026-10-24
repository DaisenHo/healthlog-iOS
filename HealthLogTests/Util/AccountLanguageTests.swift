import Foundation
@testable import HealthLog
import Testing

@Suite("Account language presentation")
struct AccountLanguageTests {
    @Test("Explicit language overrides retain the English fallback for an incomplete catalog")
    func explicitLocaleAndFallback() {
        #expect(MetricTypeLocalisation.label(forType: "BODY_TEMPERATURE", locale: Locale(identifier: "zh-Hans")) == "Body temperature")
        #expect(MetricTypeLocalisation.label(forType: "WEIGHT", locale: Locale(identifier: "en")) == "Weight")
        #expect(MetricTypeLocalisation.label(forType: "WEIGHT", locale: Locale(identifier: "de")) == "Gewicht")
    }

    @Test("Foundation lookup follows the account instead of the process language")
    func localizedResourceUsesAccountLanguage() {
        let locale = AppLocale()
        for (language, title) in [(AccountLanguage.german, "Sprache"), (.english, "Language"), (.simplifiedChinese, "语言")] {
            locale.apply(language)
            #expect(String(localized: locale.resource(LocalizedStringResource("settings.language.title"))) == title)
        }
        let instrument = "phq9"
        let key = "mentalHealth.instrument.\(instrument)"
        #expect(locale.resource(String.LocalizationValue(key)).key == key)
    }

    @Test("Simplified Chinese uses the shared wire code and the Apple catalog identifier")
    func simplifiedChineseMapping() {
        #expect(AccountLanguage(tag: "zh-Hans") == .simplifiedChinese)
        #expect(AccountLanguage(tag: "zh-CN")?.rawValue == "zh-CN")
        #expect(AccountLanguage.simplifiedChinese.locale.identifier == "zh-Hans")
        #expect(AccountLanguage(tag: "zh-Hant") == nil)
        #expect(AccountLanguage(tag: "invalid") == nil)
    }

    @Test("Presentation uses the account choice and returns to the system language on logout")
    func accountChoiceAndLogout() {
        let locale = AppLocale()
        locale.apply(.german)
        #expect(locale.current.language.languageCode?.identifier == "de")
        locale.apply(.english)
        #expect(locale.current.language.languageCode?.identifier == "en")
        locale.apply(nil)
        #expect(locale.current == Locale.autoupdatingCurrent)
    }

    @Test("A restored cache belongs to exactly one server and account and clears on logout")
    func cacheOwnershipAndRestart() throws {
        let suite = "AccountLanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = AccountLanguageCache(defaults: defaults)
        cache.save(.simplifiedChinese, ownerID: "sample-owner", server: "https://one.example.test")
        #expect(!String(describing: defaults.persistentDomain(forName: suite)).contains("one.example.test"))
        let restarted = AccountLanguageCache(defaults: defaults)
        #expect(restarted.load(ownerID: "sample-owner", server: "https://one.example.test") == .simplifiedChinese)
        #expect(restarted.load(ownerID: "other-owner", server: "https://one.example.test") == nil)
        #expect(restarted.load(ownerID: "sample-owner", server: "https://other.example.test") == nil)
        restarted.clear()
        #expect(cache.load(ownerID: "sample-owner", server: "https://one.example.test") == nil)
    }
}
