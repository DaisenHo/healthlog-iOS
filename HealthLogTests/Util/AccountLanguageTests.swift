import Foundation
@testable import HealthLog
import Testing

@Suite("Account language presentation")
struct AccountLanguageTests {
    @Test("Health-module labels follow the account language and unvalidated items stay English")
    func explicitLocaleAndFallback() {
        #expect(MetricTypeLocalisation.label(forType: "BODY_TEMPERATURE", locale: Locale(identifier: "zh-Hans")) == "体温")
        #expect(MetricTypeLocalisation.label(forType: "WEIGHT", locale: Locale(identifier: "zh-Hans")) == "体重")
        #expect(MetricTypeLocalisation.label(forType: "BLOOD_PRESSURE", locale: Locale(identifier: "zh-Hans")) == "血压")
        #expect(MetricTypeLocalisation.label(forType: "WEIGHT", locale: Locale(identifier: "en")) == "Weight")
        #expect(MetricTypeLocalisation.label(forType: "WEIGHT", locale: Locale(identifier: "de")) == "Gewicht")
        let locale = AppLocale()
        locale.apply(.simplifiedChinese)
        let item = locale.resource(LocalizedStringResource("mentalHealth.items.phq9.1"))
        #expect(String(localized: item) == "Little interest or pleasure in doing things")
        let note = locale.resource(LocalizedStringResource("mentalHealth.validatedInEnglishNote"))
        #expect(String(localized: note) == "此问卷的英文版本已受验证；题目使用英文原文显示。")
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
