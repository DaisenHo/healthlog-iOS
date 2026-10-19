// Labs grouping derivations, split out of `LabsStore.swift` (pure move,
// W-FILELEN). 14-03 added the biomarker-catalogue failure slot and its
// publication arm to the store; these three pure derivations — panel groups,
// analyte groups, the flat chronological sort — depend on nothing but `labs`
// and are the natural half to move so the host file stays under its ceiling.
//
// Nothing here changed: same bucketing, same case-insensitive analyte identity,
// same ordering, same nested types.
import Foundation

public extension LabsStore {
    // MARK: - Grouping (computed; render helper)

    /// One panel section + its rows, panel-name-ordered (un-paneled rows last
    /// under a `nil` key). Within a section rows keep the server order
    /// (newest-first). Pure derivation — no recompute of any server value.
    struct PanelGroup: Identifiable, Sendable, Equatable {
        /// `nil` for the "Other / no panel" bucket.
        public let panel: String?
        public let rows: [LabResultDTO]
        public var id: String {
            panel ?? "\u{0000}__nopanel"
        }

        public init(panel: String?, rows: [LabResultDTO]) {
            self.panel = panel
            self.rows = rows
        }
    }

    /// Labs grouped by `panel`, named panels first (alphabetical, case-insensitive),
    /// the un-paneled bucket last.
    var groupedByPanel: [PanelGroup] {
        var order: [String?] = []
        var buckets: [String: [LabResultDTO]] = [:]
        var noPanel: [LabResultDTO] = []
        for row in labs {
            if let panel = row.panel, !panel.isEmpty {
                if buckets[panel] == nil {
                    buckets[panel] = []
                    order.append(panel)
                }
                buckets[panel]?.append(row)
            } else {
                noPanel.append(row)
            }
        }
        let named = order
            .compactMap { $0 }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { PanelGroup(panel: $0, rows: buckets[$0] ?? []) }
        if noPanel.isEmpty {
            return named
        }
        return named + [PanelGroup(panel: nil, rows: noPanel)]
    }

    /// One analyte section + its rows, analyte-name-ordered (alphabetical,
    /// case-insensitive). The empty-analyte bucket (legacy rows with a blank
    /// `analyte`) sorts last under a `nil` key. Within a section rows keep the
    /// server order (newest-first). Mirrors ``PanelGroup``'s shape so the screen's
    /// section ForEach is identical across the two sort modes. Pure derivation.
    struct AnalyteGroup: Identifiable, Sendable, Equatable {
        /// `nil` for the "Other / no analyte" bucket (blank analyte string).
        public let analyte: String?
        public let rows: [LabResultDTO]
        public var id: String {
            analyte ?? "\u{0000}__noanalyte"
        }

        public init(analyte: String?, rows: [LabResultDTO]) {
            self.analyte = analyte
            self.rows = rows
        }
    }

    /// Labs grouped by `analyte` (the test/type name) — the "by type" sort axis,
    /// the closest analogue to Messwerte's `MetricKind` grouping. Named analytes
    /// first (alphabetical, case-insensitive); the blank-analyte bucket last.
    /// Pure derivation — no recompute of any server value.
    ///
    /// Bucketing is **case-insensitive** so "GGT" and "ggt" land in one row — the
    /// same identity `BiomarkerDetailScreen`'s `rows(forAnalyte:)` aggregates with
    /// `localizedCaseInsensitiveCompare`. Otherwise an index row count would
    /// disagree with the detail "Alle Messungen" count for the same analyte. The
    /// first-seen casing is kept as the canonical display name.
    var groupedByAnalyte: [AnalyteGroup] {
        var order: [String] = []
        var displayName: [String: String] = [:]
        var buckets: [String: [LabResultDTO]] = [:]
        var noAnalyte: [LabResultDTO] = []
        for row in labs {
            let analyte = row.analyte
            if analyte.isEmpty {
                noAnalyte.append(row)
            } else {
                let key = analyte.lowercased()
                if buckets[key] == nil {
                    buckets[key] = []
                    displayName[key] = analyte
                    order.append(key)
                }
                buckets[key]?.append(row)
            }
        }
        let named = order
            .sorted { (displayName[$0] ?? $0).localizedCaseInsensitiveCompare(displayName[$1] ?? $1) == .orderedAscending }
            .map { AnalyteGroup(analyte: displayName[$0] ?? $0, rows: buckets[$0] ?? []) }
        if noAnalyte.isEmpty {
            return named
        }
        return named + [AnalyteGroup(analyte: nil, rows: noAnalyte)]
    }

    /// #130 — one row of the "by type" marker list.
    struct MarkerIndexEntry: Identifiable, Sendable, Equatable {
        /// Overview `key` (`bm:<id>` / `analyte:<name>`), or the lower-cased
        /// analyte on the fallback path.
        public let id: String
        /// The analyte the detail page filters by.
        public let analyte: String
        /// Catalog name when the marker is linked, else the analyte.
        public let name: String
        public let biomarkerId: String?
        public let latest: LabResultDTO
        /// Every live reading of the marker, as the server counts them.
        public let count: Int
    }

    /// #130 — the marker list. From the server's overview when there is one
    /// (every marker over the whole history, count and newest reading as
    /// delivered); otherwise, against a server before v1.42.4, from grouping the
    /// loaded ``labs`` page as before. Named markers only, alphabetical; the
    /// blank-analyte rows stay in their own inline section.
    var markerIndex: [MarkerIndexEntry] {
        let catalogName: (String?) -> String? = { id in
            guard let id else { return nil }
            return self.biomarkers.first { $0.id == id }?.name
        }
        let entries: [MarkerIndexEntry] = if let overview = markerOverview {
            overview.markers.compactMap { marker in
                let analyte = marker.latest.analyte
                guard !analyte.isEmpty else { return nil }
                let biomarkerId = marker.biomarkerId ?? marker.latest.biomarkerId
                let name = catalogName(biomarkerId).flatMap { $0.isEmpty ? nil : $0 } ?? analyte
                return MarkerIndexEntry(
                    id: marker.key,
                    analyte: analyte,
                    name: name,
                    biomarkerId: biomarkerId,
                    latest: marker.latest,
                    count: marker.count
                )
            }
        } else {
            groupedByAnalyte.compactMap { group in
                guard let analyte = group.analyte, let latest = group.rows.first else { return nil }
                let biomarkerId = group.rows.first(where: { $0.biomarkerId != nil })?.biomarkerId
                let name = catalogName(biomarkerId).flatMap { $0.isEmpty ? nil : $0 } ?? analyte
                return MarkerIndexEntry(
                    id: analyte.lowercased(),
                    analyte: analyte,
                    name: name,
                    biomarkerId: biomarkerId,
                    latest: latest,
                    count: group.rows.count
                )
            }
        }
        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// All labs in a single flat list sorted by collection date, newest-first —
    /// the "chronological" sort axis. `takenAt` is an ISO-8601 wire string that
    /// sorts lexicographically (zero-padded fields, fixed `Z` offset), so the
    /// string compare matches chronological order without parsing. Pure derivation.
    var sortedByDate: [LabResultDTO] {
        labs.sorted { $0.takenAt > $1.takenAt }
    }
}
