import SwiftUI

/// v0.5.5.7 RECONCILE-COMPARE — benchmark comparison band for the
/// `PersonalRecordsScreen`.
///
/// #135 (server v1.43) — the band is the server's `benchmark` on the record
/// (``RecordBenchmarkBand``): its two edges as a stripe, the person's best as
/// a tick, a one-line position ("within the typical range") and the server's
/// citation. No mean marker and no "favourable" sentence: the server sends
/// neither, and the app adds no judgement of its own. Tapping the band opens
/// `BenchmarkSourceSheet` with the citation and the named references.
///
/// **Slot in the screen:** between `MilestoneStrip` and the footer, one band
/// per record kind whose record carries a benchmark; nothing when none does.
///
/// **Theme-2.0 contract:** the band uses the mono surface scale
/// (`HLSurface.tertiary` recessed well + `HLAccent.userBrandTint` for the user
/// tick + `HLText.secondary` for the band stripe). No per-kind tinting.
///
/// **Accessibility:** one VoiceOver element with the metric, the value, the
/// band and the position line, so nobody has to swipe through the geometry.
struct ComparisonBand: View {
    let record: PersonalRecord
    let band: RecordBenchmarkBand
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: HLSpace.sm) {
                header
                bar
                summary
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HLSpace.lg)
            .background(HLSurface.secondary, in: RoundedRectangle(cornerRadius: HLRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HLRadius.card, style: .continuous)
                    .stroke(HLColor.separator, lineWidth: 0.5)
            }
        }
        .buttonStyle(HLPressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(Text(LocalizedStringKey(Layout.accessibilityHint)))
        .accessibilityIdentifier("records.comparison.\(record.id)")
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: HLSpace.xs) {
            Image(systemName: "chart.bar.xaxis")
                .font(.hlIcon(HLIconSize.rowAction))
                .foregroundStyle(HLText.secondary)
                .accessibilityHidden(true)
            HLSectionLabel(LocalizedStringKey(Layout.eyebrow))
            Spacer(minLength: 0)
            Text(metricLabel)
                .font(.hlCaption.weight(.semibold))
                .foregroundStyle(HLText.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var bar: some View {
        GeometryReader { geo in
            let width = Double(geo.size.width)
            ZStack(alignment: .leading) {
                // Track — full domain.
                Capsule()
                    .fill(HLSurface.tertiary)
                    .frame(height: Layout.trackHeight)

                // The server's band.
                if let lo = band.position(of: band.low, width: width),
                   let hi = band.position(of: band.high, width: width)
                {
                    Capsule()
                        .fill(HLText.secondary.opacity(HLOpacity.surfaceTintStrong))
                        .frame(width: max(0, hi - lo), height: Layout.trackHeight)
                        .offset(x: lo)
                }

                // The person's best — accent tick against the mono band.
                if let userX = band.position(of: band.value, width: width) {
                    Capsule()
                        .fill(HLAccent.userBrandTint)
                        .frame(width: Layout.tickWidth, height: Layout.trackHeight + 6)
                        .offset(x: userX - Layout.tickWidth / 2, y: -3)
                }
            }
            .frame(width: geo.size.width, height: Layout.trackHeight + 6, alignment: .leading)
        }
        .frame(height: Layout.trackHeight + 6)
        .accessibilityHidden(true)
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: HLSpace.xs) {
            VStack(alignment: .leading, spacing: HLSpace.xxs) {
                Text(band.summary)
                    .font(.hlSubhead)
                    .foregroundStyle(HLText.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: "records.comparison.range \(band.formattedRange)"))
                    .font(.hlCaption)
                    .foregroundStyle(HLText.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                if !band.sourceLabel.isEmpty {
                    Text(band.sourceLabel)
                        .font(.hlCaption)
                        .foregroundStyle(HLText.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "info.circle")
                .font(.hlIcon(HLIconSize.rowAction))
                .foregroundStyle(HLText.tertiary)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Copy

    private var metricLabel: String {
        if let kind = record.kind {
            return kind.displayName
        }
        return MetricTypeLocalisation.label(forType: record.base.metricType)
    }

    private var accessibilityLabel: Text {
        Text(
            "records.comparison.a11y \(metricLabel) \(band.formattedValue) \(RecordBenchmarkBand.format(band.low)) \(band.formattedHigh) \(band.summary)"
        )
    }
}

extension RecordBenchmarkBand {
    /// The upper edge with its unit, for the spoken "from … to …".
    var formattedHigh: String {
        unit.isEmpty ? Self.format(high) : "\(Self.format(high)) \(unit)"
    }
}

extension ComparisonBand {
    enum Layout {
        static let trackHeight: CGFloat = 10
        static let tickWidth: CGFloat = 6

        // L1 — catalog keys, never German literals rendered verbatim.
        static let eyebrow = "benchmark.source.eyebrow"
        static let accessibilityHint = "records.comparison.a11yHint"
    }
}

#Preview("ComparisonBand — VO2 max inside the band") {
    let dto = PersonalRecordDTO(
        id: "preview.vo2",
        userId: "u1",
        metricType: "VO2_MAX",
        metricSlot: nil,
        direction: .max,
        value: 41,
        unit: "ml/kg/min",
        achievedAt: Date(),
        sourceMeasurementId: nil,
        source: "HEALTHKIT",
        externalId: nil,
        createdAt: Date(),
        benchmark: RecordBenchmark(low: 35, high: 43, unit: "ml/kg/min", source: "acsm", sourceLabel: "ACSM, 11th edition")
    )
    let record = PersonalRecord(
        id: dto.id,
        base: dto,
        kind: .vo2Max,
        sparklineValues: [],
        peakIndex: nil,
        previousValue: nil,
        bucket: .month,
        impressiveness: 0.7
    )
    let band = RecordBenchmarkBand(low: 35, high: 43, value: 41, unit: "ml/kg/min", sourceLabel: "ACSM, 11th edition")
    return ComparisonBand(record: record, band: band, onTap: {})
        .padding()
        .background(HLSurface.primary)
}
