import Foundation
@testable import HealthLog
import Testing

@Suite("T08 medication, targets and notifications localization")
struct T08LocalizationTests {
    @Test("In-scope strings have Chinese translations with matching format arguments")
    func catalogCoverage() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let coverageURL = root.appendingPathComponent("docs/project/t08-localization-coverage.json")
        let coverage = try JSONDecoder().decode(Coverage.self, from: Data(contentsOf: coverageURL))
        let catalog = try ParityCatalog.load()
        let catalogURL = root.appendingPathComponent("HealthLog/Resources/Localizable.xcstrings")
        let raw = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any])
        let strings = try #require(raw["strings"] as? [String: [String: Any]])
        #expect(!coverage.keys.isEmpty)
        for key in coverage.keys {
            let entry = try #require(catalog.strings[key], "Missing catalog key: \(key)")
            for language in ["de", "en", "zh-Hans"] {
                #expect(ParityCatalog.hasLocalization(entry, language: language), "Missing \(language): \(key)")
            }
            let localizations = try #require(strings[key]?["localizations"] as? [String: [String: Any]])
            let english = Self.stringValues(localizations["en"] ?? [:])
            let chinese = Self.stringValues(localizations["zh-Hans"] ?? [:])
            #expect(!english.isEmpty, "No English string units: \(key)")
            #expect(Set(english.keys) == Set(chinese.keys), "Missing Chinese plural or substitution: \(key)")
            for (path, value) in english {
                let translated = try #require(chinese[path], "Missing Chinese string unit: \(key)/\(path)")
                #expect(!translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(
                    CatalogFormatSignatureTests.argumentSignature(of: translated)
                        == CatalogFormatSignatureTests.argumentSignature(of: value),
                    "Format arguments differ: \(key)"
                )
            }
        }
    }

    @Test("Chinese and English resolve medication provenance, reminders, targets and errors")
    func accountLanguageCopy() {
        let locale = AppLocale()
        let samples: [String: (english: String, chinese: String)] = [
            "medications.appleHealth.provenance": ("From Apple Health", "来自 Apple 健康"),
            "vorsorge.history.source.manual": ("Entered manually", "手动录入"),
            "Snooze 15 min": ("Snooze 15 min", "15 分钟后提醒"),
            "Medication not found": ("Medication not found", "未找到药品"),
            "Target range": ("Target range", "目标范围"),
            "reminders.create.rrule.weekly": ("Weekly", "每周"),
            "reminders.create.cadence.label": ("Cadence", "提醒周期"),
            "medication.quick_mark.not_scheduled_today": ("No intake today", "今天无服药记录"),
            "med.schedule.times.header": ("Reminder times", "提醒时间")
        ]
        for (language, isChinese) in [(AccountLanguage.simplifiedChinese, true), (.english, false)] {
            locale.apply(language)
            for (key, expected) in samples {
                let resource = locale.resource(String.LocalizationValue(key))
                #expect(String(localized: resource) == (isChinese ? expected.chinese : expected.english))
            }
            let medication = "SampleMedicine"
            let resource = locale.resource(LocalizedStringResource("med.ledger.dose_deviation.a11y"))
            let dose = String(format: String(localized: resource), medication)
            #expect(dose == (isChinese ? "已服用：SampleMedicine" : "Dose taken: SampleMedicine"))
            let provenance = locale.resource(DoseIntakeProvenance.appleHealth.labelResource)
            #expect(String(localized: provenance) == (isChinese ? "Apple 健康" : "Apple Health"))
            let channel = locale.resource(LocalizedStringResource("notifications.channel.state.inactive"))
            #expect(String(localized: channel) == (isChinese ? "未启用" : "Inactive"))
            let delivery = locale.resource(LocalizedStringResource("med.edit.delivery.section"))
            #expect(String(localized: delivery) == (isChinese ? "提醒方式" : "Delivery"))
            let weeksOn = 2
            let weeksOff = 1
            let cycle = locale.resource(LocalizedStringResource("med.schedule.cadence.cyclic.preview \(weeksOn) \(weeksOff)"))
            #expect(String(localized: cycle) == (isChinese ? "服用 2 周，停用 1 周。" : "2 weeks on, 1 week off."))
        }
    }

    private static func stringValues(_ node: [String: Any]) -> [String: String] {
        var values: [String: String] = [:]
        for (key, value) in node {
            guard let child = value as? [String: Any] else { continue }
            if key == "stringUnit", let text = child["value"] as? String {
                values[key] = text
            } else {
                for (path, text) in stringValues(child) {
                    values["\(key)/\(path)"] = text
                }
            }
        }
        return values
    }

    private struct Coverage: Decodable {
        let keys: [String]
    }
}
