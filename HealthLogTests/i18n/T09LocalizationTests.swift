import Foundation
@testable import HealthLog
import PDFKit
import Testing

@Suite("T09 reports, permissions, extensions and remaining app localization", .serialized)
struct T09LocalizationTests {
    @MainActor
    @Test("ReportLocale resolves server codes and renders Chinese on-device doctor report PDF")
    func chineseDoctorReportAndFallback() async throws {
        #expect(ReportLocale(serverCode: "zh-CN") == .zh)
        #expect(ReportLocale(serverCode: "zh-Hans") == .zh)
        #expect(ReportLocale(serverCode: "de") == .de)
        #expect(ReportLocale(serverCode: "en") == .en)
        #expect(DoctorReportDisclaimer.text(for: .zh) == DoctorReportDisclaimer.zh)
        #expect(PDFMeta.title(for: .zh) == "医生报告")

        let spec = Self.makeSampleChineseReportSpec()
        #expect(spec.cover.locale == .zh)
        #expect(spec.footer.disclaimer == DoctorReportDisclaimer.zh)

        let block = try #require(spec.adherence)
        let notes = LocaleText.adherenceNotes(for: block, locale: .zh)
        #expect(notes.first?.contains("过去 30 天的服药依从性") == true)
        let firstRow = try #require(block.perMedication.first)
        let rowText = LocaleText.adherenceRow(firstRow, windowDays: 30, locale: .zh)
        #expect(rowText.contains("Amlodipin"))
        #expect(rowText.contains("27"))

        let renderer = DoctorReportRenderer()
        let data = try await renderer.renderData(spec)
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 6)
        let coverText = try #require(document.page(at: 0)?.string)
        #expect(coverText.contains("医生报告"))
        #expect(coverText.contains("张伟"))
        #expect(coverText.contains("本地导出"))
        #expect(coverText.contains("非医疗文件"))
        let vitalsText = try #require(document.page(at: 1)?.string)
        #expect(vitalsText.contains("生命体征"))
        #expect(vitalsText.contains("血压"))

        let tile = ChartTile(
            series: .init(kind: .bloodPressure, points: [.init(at: spec.cover.periodEnd, value: 122, secondary: 78)]),
            locale: .zh
        )
        #expect(tile.title == "血压")
    }

    @Test("Mini-Coach refusal, unsupported fallback, classifier, and cache invalidation cover Chinese")
    func miniCoachAndCacheInvalidationChinese() async throws {
        let zhLocale = Locale(identifier: "zh-Hans")
        let refusal = MiniCoachPrompt.refusalCopy(locale: zhLocale)
        let unsupported = MiniCoachPrompt.unsupportedFallback(locale: zhLocale)
        let prompt = MiniCoachPrompt.userTurn(
            ask: "我最近一次体重是多少？",
            category: .dataLookup,
            boundContext: "体重: 68.5 kg",
            history: [.init(role: .user, text: "你好")],
            locale: zhLocale
        )
        #expect(refusal.contains("记录的数据"))
        #expect(unsupported.contains("iOS 26"))
        #expect(prompt.contains("用户提问"))
        #expect(prompt.contains("此前对话记录"))

        let classifier = MiniCoachAskClassifier()
        #expect(await classifier.classify("我最近一次体重是多少？") == .allowed(.dataLookup))
        #expect(await classifier.classify("这周情况如何？") == .allowed(.periodSummary))
        #expect(await classifier.classify("3月1日的心率？") == .allowed(.historicLookup))
        #expect(await classifier.classify("本周对比上周？") == .allowed(.comparison))
        #expect(await classifier.classify("我应该怎么改善？") == .refused(reason: .adviceRequest))

        let zone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let keys = MutationKind.measurementChange(kind: .weight).affectedKeys(profileTimeZone: zone)
        #expect(keys.contains(.metricInsights(kind: .weight, locale: "zh-CN")))
    }

    @Test("Chinese InfoPlist purpose strings and all five shipping target localizations")
    func chinesePermissionStringsAndTargetLocalizations() throws {
        let root = Self.repoRoot
        let expectedKeys = [
            "NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription",
            "NSFaceIDUsageDescription", "NSUserNotificationsUsageDescription",
            "NSAlarmKitUsageDescription", "NSSpeechRecognitionUsageDescription",
            "NSMicrophoneUsageDescription", "NSCameraUsageDescription",
            "NSBluetoothAlwaysUsageDescription"
        ]
        let chinese = try String(
            contentsOf: root.appendingPathComponent("HealthLog/Resources/zh-Hans.lproj/InfoPlist.strings"),
            encoding: .utf8
        )
        for key in expectedKeys {
            #expect(chinese.contains("\"\(key)\""), "Missing Chinese purpose string for \(key)")
        }
        for disclosure in ["Apple 健康", "心电图", "用药", "文档保险库", "服务器", "Omron"] {
            #expect(chinese.contains(disclosure), "Chinese purpose string omits \(disclosure)")
        }
        #expect(!chinese.contains("NSPhotoLibraryUsageDescription"))

        let plistPaths = [
            "HealthLog/Resources/Info.plist",
            "HealthLogWidgets/Resources/Info.plist",
            "NotificationServiceExtension/Resources/Info.plist",
            "HealthLogWatch/Info.plist",
            "HealthLogWatchWidgets/Info.plist"
        ]
        for relativePath in plistPaths {
            let data = try Data(contentsOf: root.appendingPathComponent(relativePath))
            let plist = try #require(
                try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            )
            let localizations = try #require(plist["CFBundleLocalizations"] as? [String], "Missing CFBundleLocalizations in \(relativePath)")
            #expect(Set(localizations) == ["de", "en", "zh-Hans"], "Unexpected localizations in \(relativePath): \(localizations)")
        }
    }

    @MainActor
    @Test("Companion extension catalogs have Chinese translations and account language refreshes snapshots")
    func companionCatalogsAndAccountLanguageRefresh() throws {
        let companionCatalogs = [
            "HealthLogWidgets/Resources/Localizable.xcstrings",
            "NotificationServiceExtension/Resources/Localizable.xcstrings",
            "HealthLogWatch/Resources/Localizable.xcstrings",
            "HealthLogWatchWidgets/Localizable.xcstrings"
        ]
        for relativePath in companionCatalogs {
            try Self.assertCompanionCatalog(relativePath: relativePath)
        }

        let testLocale = AppLocale()
        let api = StubAPIClient()
        let defaults = try #require(UserDefaults(suiteName: "test.t09.prefs.\(UUID().uuidString)"))
        let settings = SettingsStore(repo: SettingsRepository(api: api), defaults: defaults)
        let shared = SharedAccountPrefs(defaults: defaults, currentUserID: { "user-t09" })
        var refreshedCount = 0
        AppContainer.wireSharedAccountPrefs(
            settingsStore: settings,
            profileTimeZoneBox: ProfileTimeZoneBox(defaults: defaults, sharedPrefs: shared),
            sharedPrefs: shared,
            appLocale: testLocale,
            onGlucoseUnitChange: {},
            onAccountLanguageChange: { refreshedCount += 1 }
        )
        settings.onAccountLanguageChange?(.simplifiedChinese)
        #expect(refreshedCount == 1)
        #expect(testLocale.serverCode == "zh-CN")

        let reading = HealthLog.Measurement(
            id: "w-1",
            kind: .weight,
            recordedAt: Date(timeIntervalSince1970: 1_775_000_000),
            value: .scalar(68.5)
        )
        let widgetGlance = try #require(WidgetSnapshot.LatestMeasurement.make(from: reading, units: .standard, locale: testLocale.current))
        let watchGlance = try #require(WatchSnapshot.LatestMeasurement.make(from: reading, units: .standard, locale: testLocale.current))
        #expect(widgetGlance.title == "体重")
        #expect(watchGlance.title == "体重")
    }

    @Test("Remaining main-app catalog keys have Chinese translations with matching format signatures")
    func mainAppCatalogCoverageAndRepresentativeCopy() throws {
        let root = Self.repoRoot
        let coverageURL = root.appendingPathComponent("docs/project/t09-localization-coverage.json")
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
            try Self.assertLanguageTreeParity(localizations: localizations, context: key)
        }

        let locale = AppLocale()
        let samples: [String: (english: String, chinese: String)] = [
            "appstore.disclaimer.card_title": ("Not a Medical Device", "非医疗器械"),
            "report.leaf.MEDICATION_COMPLIANCE": ("Adherence rate", "服药依从率"),
            "spotlight.keyword.measurement": ("measurement", "测量"),
            "briefing.measurements.none": ("No measurements logged in the last 7 days.", "过去 7 天未记录测量数据。"),
            "HealthLog is locked": ("HealthLog is locked", "HealthLog 已锁定"),
            "Lousy": ("Lousy", "很差"),
            "Okay": ("Okay", "一般")
        ]
        for (language, isChinese) in [(AccountLanguage.simplifiedChinese, true), (.english, false)] {
            locale.apply(language)
            for (key, expected) in samples {
                let resource = locale.resource(String.LocalizationValue(key))
                #expect(String(localized: resource) == (isChinese ? expected.chinese : expected.english))
            }
        }
    }

    private struct Coverage: Decodable {
        let keys: [String]
    }

    private static var repoRoot: URL {
        ParityCatalog.repoRoot()
    }

    @MainActor
    private static func makeSampleChineseReportSpec() -> DoctorReportSpec {
        let start = Date(timeIntervalSince1970: 1_775_000_000)
        let end = start.addingTimeInterval(30 * 86400)
        let med = Medication(
            id: "med-1",
            name: "Amlodipin",
            dose: "5 mg",
            schedule: MedicationSchedule(times: [TimeOfDay(hour: 8, minute: 0)])
        )
        let window = ComplianceWindowResult(
            totalExpected: 30,
            taken: 27,
            skipped: 0,
            missed: 3,
            rate: 90,
            streak: 5
        )
        let snapshot = DoctorReportSpecBuilder.Snapshot(
            patientName: "张伟",
            fullName: "张伟",
            insurerName: "示例医保",
            insuranceNumber: "A123456789",
            appVersion: "1.3.0 (296)",
            measurements: [
                HealthLog.Measurement(
                    id: "bp-1",
                    kind: .bloodPressure,
                    recordedAt: start.addingTimeInterval(86400),
                    value: .bloodPressure(systolic: 122, diastolic: 78)
                )
            ],
            medications: [med],
            serverCompliance: [
                MedicationComplianceSummaryEntry(
                    medicationId: "med-1",
                    compliance7: window,
                    compliance30: window,
                    applicable: true
                )
            ],
            moodEntries: [
                MoodEntry(id: "m-1", recordedAt: start.addingTimeInterval(86400), score: 4, tags: ["平静"])
            ]
        )
        return DoctorReportSpecBuilder.build(
            snapshot: snapshot,
            periodStart: start,
            periodEnd: end,
            generatedAt: end,
            locale: .zh
        )
    }

    private static func assertCompanionCatalog(relativePath: String) throws {
        let url = repoRoot.appendingPathComponent(relativePath)
        let raw = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try #require(raw["strings"] as? [String: [String: Any]])
        #expect(!strings.isEmpty, "Empty catalog: \(relativePath)")
        if relativePath.hasPrefix("HealthLogWidgets/") {
            for moodKey in ["Lousy", "Bad", "Okay", "Good", "Great"] {
                #expect(strings[moodKey] != nil, "Missing widget mood key: \(moodKey)")
            }
        }
        for (key, entry) in strings where !key.isEmpty {
            let localizations = try #require(entry["localizations"] as? [String: [String: Any]], "No localizations: \(relativePath):\(key)")
            for lang in ["de", "en", "zh-Hans"] {
                #expect(localizations[lang] != nil, "Missing \(lang) in \(relativePath):\(key)")
            }
            try assertLanguageTreeParity(localizations: localizations, context: "\(relativePath):\(key)")
        }
    }

    private static func assertLanguageTreeParity(
        localizations: [String: [String: Any]],
        context: String
    ) throws {
        let english = ParityCatalog.stringValues(localizations["en"] ?? [:])
        let chinese = ParityCatalog.stringValues(localizations["zh-Hans"] ?? [:])
        #expect(!english.isEmpty, "No English string units: \(context)")
        #expect(Set(english.keys) == Set(chinese.keys), "Mismatched unit keys in \(context)")
        for (path, enVal) in english {
            let zhVal = try #require(chinese[path], "Missing Chinese string unit: \(context)/\(path)")
            #expect(!zhVal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(
                CatalogFormatSignatureTests.argumentSignature(of: zhVal)
                    == CatalogFormatSignatureTests.argumentSignature(of: enVal),
                "Signature mismatch in \(context)"
            )
        }
    }
}
