import SwiftUI

// MARK: - Sources attribution row (Apple-Health "Daten von:" pattern)

/// Detailed provenance audit row — keeps the iconified "Daten von" card further
/// down the scroll for users who want the full per-source breakdown after seeing
/// the at-a-glance chip strip near the top.
///
/// v0.4.1: bound to `ChartDetailStore.sourceCountsForRange` — populated from
/// `MeasurementsRepository.recent(kind:)` since the server's
/// `/api/measurements/series` doesn't carry per-point provenance yet.
///
/// **v0.11 W22-audit:** extracted out of `ChartDetailScreen.swift` (from
/// `private` → internal, no behavioural change) so the web-mirror
/// `InsightsMetricScreen` can reuse the SAME provenance row instead of
/// duplicating it — the raw-readings drill-down + sources affordance must
/// survive the W4 cutover that retires `ChartDetailScreen`. Mirrors the earlier
/// `DrillDownRow` / `InsufficientDataCard` / `HeroDeltaChip` extractions.
struct SourcesRow: View {
    let breakdown: [ChartDetailStore.SourceCount]
    let sourceFilter: MeasurementSource?

    var body: some View {
        VStack(alignment: .leading, spacing: HLSpace.sm) {
            HLSectionLabel("Data from")
            HLCard {
                VStack(alignment: .leading, spacing: HLSpace.sm) {
                    if !breakdown.isEmpty {
                        ForEach(breakdown) { entry in
                            SourceRow(source: entry.source, count: entry.count)
                            if entry.source != breakdown.last?.source {
                                Divider()
                            }
                        }
                    } else if let filter = sourceFilter {
                        SourceRow(source: filter, count: nil)
                    } else {
                        SourceRow(source: nil, count: nil)
                    }
                }
            }
        }
    }
}

private struct SourceRow: View {
    let source: MeasurementSource?
    let count: Int?

    var body: some View {
        HStack(spacing: HLSpace.md) {
            Image(systemName: iconName)
                // Glyph inside a fixed 28×28 source chip — sized via the
                // canonical HLIconSize scale; must not scale past the frame
                // (the adjacent labels carry the Dynamic Type weight).
                .font(.hlIcon(HLIconSize.rowAction))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(HLOpacity.surfaceTintStrong))
                .clipShape(RoundedRectangle(cornerRadius: HLRadius.xs, style: .continuous))
            VStack(alignment: .leading, spacing: HLSpace.xxs) {
                Text(label)
                    .font(.hlSubhead.weight(.semibold))
                    .foregroundStyle(HLText.primary)
                if let count {
                    Text("\(count) entries")
                        .font(.hlCaption)
                        .foregroundStyle(HLText.secondary)
                } else if source == nil {
                    Text("All sources")
                        .font(.hlCaption)
                        .foregroundStyle(HLText.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, HLSpace.xs)
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch source {
        case .appleHealth: "heart.text.square.fill"
        case .withings: "scale.3d"
        case .whoop: "bolt.heart.fill"
        case .fitbit: "figure.run"
        case .googleHealth: "waveform.path.ecg"
        case .strava: "figure.outdoor.cycle"
        case .oura: "circle.circle.fill"
        case .polar: "heart.circle.fill"
        case .nightscout: "drop.fill"
        case .healthConnect: "link.circle.fill"
        case .telegram: "paperplane.fill"
        case .mcp: "terminal.fill"
        case .external: "antenna.radiowaves.left.and.right"
        case .manual: "pencil.tip.crop.circle"
        case .computed: "function"
        case .import_: "square.and.arrow.down.fill"
        case .unknown: "questionmark.circle"
        case nil: "circle.grid.3x3.fill"
        }
    }

    private var tint: Color {
        // v0.6.1 mono refresh — source pills used to colour-code each
        // origin (accent / cyan / orange), now they all route through
        // HLText.secondary so the chart legend reads in a single
        // monochrome key. The SF Symbol per source still differentiates.
        HLText.secondary
    }

    private var label: String {
        switch source {
        case .appleHealth: AppLocale.string("Apple Health")
        case .withings: AppLocale.string("Withings")
        case .whoop: AppLocale.string("WHOOP")
        case .fitbit: AppLocale.string("Fitbit")
        case .googleHealth: AppLocale.string("Google Health")
        case .strava: AppLocale.string("Strava")
        case .oura: AppLocale.string("Oura")
        case .polar: AppLocale.string("Polar")
        case .nightscout: AppLocale.string("Nightscout")
        case .healthConnect: AppLocale.string("Health Connect")
        case .telegram: AppLocale.string("Telegram")
        case .mcp: AppLocale.string("MCP")
        case .external: AppLocale.string("measurement.source.external")
        case .manual: AppLocale.string("chart.source.manual")
        case .computed: AppLocale.string("measurement.source.computed")
        case .import_: AppLocale.string("Import")
        case .unknown: AppLocale.string("measurement.source.unknown")
        case nil: AppLocale.string("All sources")
        }
    }
}
