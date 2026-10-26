import Foundation

/// #115 · 1.2 — the doctor report's adherence wording (split from
/// `DoctorReportSectionDrawer.swift` for the file-length budget).
extension LocaleText {
    /// #115 · 1.2 — the sentences that frame the server's adherence.
    static func adherenceNotes(for block: DoctorReportSpec.AdherenceBlock, locale: ReportLocale) -> [String] {
        switch block.availability {
        case .unavailable:
            return [adherenceUnavailable(for: locale)]
        case .server:
            var notes = [adherenceSource(windowDays: block.windowDays, locale: locale)]
            if let account = block.account {
                notes.append(adherenceAccount(account, windowDays: block.windowDays, locale: locale))
            }
            if !block.windowMatchesPeriod {
                notes.append(adherenceWindowMismatch(windowDays: block.windowDays, periodDays: block.periodDays, locale: locale))
            }
            return notes
        }
    }

    static func adherenceRow(_ row: DoctorReportSpec.AdherenceBlock.Row, windowDays: Int, locale: ReportLocale) -> String {
        guard row.applicable, let rate = row.rate, let taken = row.taken, let expected = row.expected else {
            return locale.text(
                de: "\(row.medicationName): kein Einnahmeplan in HealthLog, keine Einnahmetreue",
                en: "\(row.medicationName): no HealthLog schedule, no adherence rate",
                zh: "\(row.medicationName)：在 HealthLog 中无用药计划，无依从率"
            )
        }
        let percent = HLNumberFormat.percent(rate, locale: Locale(identifier: locale.foundationIdentifier))
        return locale.text(
            de: "\(row.medicationName): \(taken) von \(expected) eingenommen (\(percent)) in \(windowDays) Tagen",
            en: "\(row.medicationName): \(taken) of \(expected) taken (\(percent)) in \(windowDays) days",
            zh: "\(row.medicationName)：\(windowDays) 天内应服 \(expected) 次，已服 \(taken) 次（\(percent)）"
        )
    }

    static func adherenceSource(windowDays: Int, locale: ReportLocale) -> String {
        locale.text(
            de: "Einnahmetreue der letzten \(windowDays) Tage, vom HealthLog-Server nach Einnahmeplan berechnet.",
            en: "Adherence over the last \(windowDays) days, computed by the HealthLog server from the dosing schedule.",
            zh: "过去 \(windowDays) 天的服药依从性，由 HealthLog 服务器根据用药计划计算。"
        )
    }

    static func adherenceWindowMismatch(windowDays: Int, periodDays: Int, locale: ReportLocale) -> String {
        locale.text(
            de: "Fuer den Berichtszeitraum von \(periodDays) Tagen liefert der Server keine Einnahmetreue; gezeigt sind die letzten \(windowDays) Tage.",
            en: "The server provides no adherence for the \(periodDays)-day report period; the last \(windowDays) days are shown.",
            zh: "服务器未提供 \(periodDays) 天报告时段的服药依从性；此处显示过去 \(windowDays) 天的数据。"
        )
    }

    static func adherenceUnavailable(for locale: ReportLocale) -> String {
        locale.text(
            de: "Einnahmetreue nicht verfuegbar: Der HealthLog-Server war beim Erstellen nicht erreichbar.",
            en: "Adherence not available: the HealthLog server could not be reached when this report was made.",
            zh: "服药依从性不可用：生成此报告时无法连接 HealthLog 服务器。"
        )
    }
}

/// #126 P2 (server v1.42.0) — the report's own adherence window.
///
/// `?days=` (the report period, 30/60/90/180/365) adds `complianceN` to every
/// row and to the account figure. The window is used only when the server
/// answered for exactly the period and for every applicable medication the
/// report lists; otherwise the block stays on `compliance30` and says so. Rows
/// are never mixed across windows.
struct DoctorReportAdherenceWindow {
    let days: Int
    let rows: [String: ComplianceWindowResult]

    init?(report: MedicationComplianceReport?, periodDays: Int, medications: [Medication]) {
        guard let report, let days = report.days, days == periodDays else { return nil }
        let applicable = report.entries.filter(\.isApplicable).map(\.medicationId)
        let listed = Set(medications.map(\.id))
        let needed = applicable.filter { listed.contains($0) }
        guard needed.allSatisfy({ report.rowWindows[$0] != nil }) else { return nil }
        self.days = days
        rows = report.rowWindows
    }

    /// The account figure for `days`, as the server sent it.
    static func accountFigure(
        _ aggregate: MedicationComplianceAggregate?,
        days: Int
    ) -> DoctorReportSpec.AdherenceBlock.AccountFigure? {
        guard let aggregate, let window = aggregate.window(days: days) else { return nil }
        return .init(
            rate: window.rate,
            taken: window.taken,
            expected: window.taken + window.missed,
            medicationCount: aggregate.medicationCount
        )
    }
}

extension LocaleText {
    /// #126 P2 — the account line under the source note.
    static func adherenceAccount(
        _ figure: DoctorReportSpec.AdherenceBlock.AccountFigure,
        windowDays: Int,
        locale: ReportLocale
    ) -> String {
        let percent = HLNumberFormat.percent(figure.rate, locale: Locale(identifier: locale.foundationIdentifier))
        return locale.text(
            de: "Alle Medikamente (\(figure.medicationCount)): \(figure.taken) von \(figure.expected) eingenommen (\(percent)) in \(windowDays) Tagen",
            en: "All medications (\(figure.medicationCount)): \(figure.taken) of \(figure.expected) taken (\(percent)) in \(windowDays) days",
            zh: "全部药物（\(figure.medicationCount)）：\(windowDays) 天内应服 \(figure.expected) 次，已服 \(figure.taken) 次（\(percent)）"
        )
    }
}
