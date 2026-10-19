import Foundation

/// #126 P2 (server v1.42.0, #116 items 1 and 2) — the account figure and
/// the report window of `GET /api/medications/compliance`.
///
/// `meta.aggregate` is ONE adherence figure for the whole account, weighted by
/// expected doses across the applicable medications (`null` when none
/// applies), so the app never averages the per-medication rates. `?days=` (30,
/// 60, 90, 180 or 365) adds a `complianceN` block in the same shape to every row
/// and to the aggregate, for a report that covers its own window; 30 is the
/// existing `compliance30`. A server older than v1.42.0 sends no `meta`.
public struct MedicationComplianceAggregate: Decodable, Sendable, Equatable {
    public let compliance7: ComplianceWindowResult
    public let compliance30: ComplianceWindowResult
    /// `compliance60` / `compliance90` / `compliance180` / `compliance365`, when
    /// the request named that window.
    public let extraWindows: [Int: ComplianceWindowResult]
    /// How many applicable medications the figure is built from.
    public let medicationCount: Int

    public init(
        compliance7: ComplianceWindowResult,
        compliance30: ComplianceWindowResult,
        extraWindows: [Int: ComplianceWindowResult] = [:],
        medicationCount: Int
    ) {
        self.compliance7 = compliance7
        self.compliance30 = compliance30
        self.extraWindows = extraWindows
        self.medicationCount = medicationCount
    }

    private enum CodingKeys: String, CodingKey {
        case compliance7, compliance30, medicationCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        compliance7 = try c.decode(ComplianceWindowResult.self, forKey: .compliance7)
        compliance30 = try c.decode(ComplianceWindowResult.self, forKey: .compliance30)
        medicationCount = (try? c.decodeIfPresent(Int.self, forKey: .medicationCount)) ?? 0
        extraWindows = try ComplianceExtraWindows(from: decoder).windows
    }

    /// The figure for `days` (7, 30, or a requested report window).
    public func window(days: Int) -> ComplianceWindowResult? {
        switch days {
        case 7: compliance7
        case 30: compliance30
        default: extraWindows[days]
        }
    }
}

/// The `complianceN` blocks a `?days=` request adds (60, 90, 180, 365).
/// Tolerant: a block that is absent, `null` or unreadable is simply missing.
struct ComplianceExtraWindows: Decodable {
    static let reportWindows = [60, 90, 180, 365]

    let windows: [Int: ComplianceWindowResult]

    private struct Key: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue _: Int) {
            nil
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        var found: [Int: ComplianceWindowResult] = [:]
        for days in Self.reportWindows {
            if let value = try? c.decodeIfPresent(ComplianceWindowResult.self, forKey: Key(stringValue: "compliance\(days)")) {
                found[days] = value
            }
        }
        windows = found
    }
}

/// The whole batched read: the rows as before, plus the account figure and the
/// per-row figure for the requested window.
public struct MedicationComplianceReport: Sendable, Equatable {
    public let entries: [MedicationComplianceSummaryEntry]
    /// `nil` on a server before v1.42.0, or when no medication applies.
    public let aggregate: MedicationComplianceAggregate?
    /// The `days` the request asked for (`nil` = none).
    public let days: Int?
    /// Per medication, the figure for `days` (30 reads `compliance30`).
    public let rowWindows: [String: ComplianceWindowResult]

    public init(
        entries: [MedicationComplianceSummaryEntry],
        aggregate: MedicationComplianceAggregate? = nil,
        days: Int? = nil,
        rowWindows: [String: ComplianceWindowResult] = [:]
    ) {
        self.entries = entries
        self.aggregate = aggregate
        self.days = days
        self.rowWindows = rowWindows
    }

    /// The `days` values the route accepts; any other is a 422 server-side.
    public static let acceptedDays: Set<Int> = [30, 60, 90, 180, 365]
}

/// Wire envelope of the batched read with its `meta`. `data` decodes twice:
/// once as the rows the app already reads, once for the `complianceN` blocks.
struct MedicationComplianceListWire: Decodable {
    let report: MedicationComplianceReport

    private enum CodingKeys: String, CodingKey {
        case data, meta
    }

    private struct Meta: Decodable {
        let aggregate: MedicationComplianceAggregate?
        let days: Int?

        private enum CodingKeys: String, CodingKey {
            case aggregate, days
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            aggregate = try? c.decodeIfPresent(MedicationComplianceAggregate.self, forKey: .aggregate)
            days = try? c.decodeIfPresent(Int.self, forKey: .days)
        }
    }

    private struct RowWindows: Decodable {
        let medicationId: String
        let extra: ComplianceExtraWindows

        private enum CodingKeys: String, CodingKey {
            case medicationId
        }

        init(from decoder: Decoder) throws {
            medicationId = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .medicationId)
            extra = try ComplianceExtraWindows(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try c.decode([MedicationComplianceSummaryEntry].self, forKey: .data)
        let rows = (try? c.decode([RowWindows].self, forKey: .data)) ?? []
        let meta = try? c.decodeIfPresent(Meta.self, forKey: .meta)
        let days = meta?.days
        var rowWindows: [String: ComplianceWindowResult] = [:]
        if let days {
            if days == 30 {
                for entry in entries {
                    rowWindows[entry.medicationId] = entry.compliance30
                }
            } else {
                for row in rows {
                    if let value = row.extra.windows[days] { rowWindows[row.medicationId] = value }
                }
            }
        }
        report = MedicationComplianceReport(
            entries: entries,
            aggregate: meta?.aggregate,
            days: days,
            rowWindows: rowWindows
        )
    }
}
