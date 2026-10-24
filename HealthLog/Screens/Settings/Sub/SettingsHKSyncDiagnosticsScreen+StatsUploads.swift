import SwiftUI

/// **V1 (1.2, #66 / HealthLog#1173)** — when each summed or averaged type last
/// reached the server, and which trigger carried it.
///
/// The five day totals (steps, active energy, flights, distance, daylight) and
/// the pulse buckets go up as `stats:` rows, not as single readings, so the
/// per-kind list above (session counters, reset on every launch) cannot answer
/// whether they arrived on their own overnight. This card reads the persistent
/// per-account record (``HealthKitStatsUploadLog``). A row whose time moves on
/// with "Background" or "Foreground" next to it, without anybody pressing
/// "Sync all", is the evidence the server team asked for.
///
/// **W5 (1.3.0)** — this is a local record and now says so. A type with no
/// upload here ("none sent from this iPhone yet") can still have reached the
/// server as single readings, so each row carries the server's own line for
/// the same type underneath.
extension SettingsHKSyncDiagnosticsScreen {
    /// The identifiers this card lists, in display order.
    static let statsUploadIdentifiers: [String] = HealthKitCumulativeTypeConfig.defaults.map(\.identifier)
        + [HealthKitHRBucketRow.hkIdentifier]

    var statsUploadCard: some View {
        HLSettingsCard(
            icon: "sum",
            title: "settings.hkdiag.stats.title",
            footer: "settings.hkdiag.stats.footer"
        ) {
            VStack(alignment: .leading, spacing: HLSpace.md) {
                HKSyncDiagnosticsSourceTag(source: .deviceStored)
                statRow(label: "settings.hkdiag.stats.last_sweep", value: statsEventLabel(statsUploadLog?.lastSweep))
                ForEach(Self.statsUploadIdentifiers, id: \.self) { identifier in
                    VStack(alignment: .leading, spacing: HLSpace.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: HLSpace.md) {
                            Text(Self.statsTypeTitle(identifier))
                                .font(.hlCaption)
                                .foregroundStyle(HLText.primary)
                            Spacer(minLength: HLSpace.sm)
                            Text(Self.statsSentLabel(statsUploadLog?.uploads[identifier]))
                                .font(.hlCaption.monospacedDigit())
                                .foregroundStyle(HLText.tertiary)
                                .multilineTextAlignment(.trailing)
                        }
                        // W5 — the server's word for the same type, so "none
                        // sent from this iPhone" and "received 5 hours ago" read
                        // as two facts, not a contradiction (pulse can arrive as
                        // single readings).
                        if let line = Self.statsServerLine(identifier, freshness: serverSummary?.freshness) {
                            Text(verbatim: line)
                                .font(.hlCaption2)
                                .foregroundStyle(HLText.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .accessibilityIdentifier("settings.hkdiag.statsUploads")
    }

    func loadStatsUploads() {
        let userID = container?.keychain.getString(forKey: KeychainKey.userID)
        statsUploadLog = HealthKitStatsUploadLogStore.load(ownerID: userID)
    }

    /// "5 minutes ago, Background", or "Never".
    func statsEventLabel(_ entry: HealthKitStatsUploadLog.Entry?) -> String {
        guard let entry else { return AppLocale.string("settings.hkdiag.never") }
        let trigger = HKSyncDiagnosticsVocabulary.collectionTrigger(entry.trigger)
        return "\(relativeOrNever(entry.at)), \(trigger)"
    }

    /// W5 — "New value sent 5 minutes ago, Background", or "None sent from
    /// this iPhone yet": a local record, and it says so.
    static func statsSentLabel(_ entry: HealthKitStatsUploadLog.Entry?) -> String {
        guard let entry else { return AppLocale.string("settings.hkdiag.stats.none_sent") }
        let when = ServerFreshnessFacts.relative(entry.at)
        let trigger = HKSyncDiagnosticsVocabulary.collectionTrigger(entry.trigger)
        return AppLocale.string("settings.hkdiag.stats.sent \(when) \(trigger)")
    }

    /// W5 — "Server: last checked 5 hours ago (Background)" for the same type,
    /// or `nil` when the server has no row for it (or no receipt fields).
    static func statsServerLine(_ identifier: String, freshness: [MetricFreshness]?) -> String? {
        guard let row = ServerFreshnessFacts.row(forHealthKitIdentifier: identifier, in: freshness),
              let checked = ServerFreshnessFacts(row: row).checkedLabel else { return nil }
        return AppLocale.string("settings.hkdiag.stats.server_line \(checked)")
    }

    static func statsTypeTitle(_ identifier: String) -> String {
        guard let kind = HKSyncDiagnostics.metricKind(for: identifier) else { return identifier }
        return AppLocale.string(AppLocale.shared.resource(kind.descriptor.title))
    }
}
