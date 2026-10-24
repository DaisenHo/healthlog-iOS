import Charts
import SwiftUI

/// #135 (server v1.43) — the reference lines the series route asks a chart to
/// draw (`referenceLines`: value, edge, source, label). The app draws them as
/// delivered and owns no threshold of its own: no line is placed, moved,
/// merged or dropped here, and an older server that sends none draws none
/// (the empty ``MetricChartContent/clinicalThresholds(for:)`` stays empty).
///
/// Style follows the existing threshold rules (`HLChartGrid`): an upper edge
/// in `thresholdHigh`, a lower edge in `thresholdLow`. A clinical line is
/// dashed, a line the person set themselves is solid. The label rides above
/// the line in the caption font, so it scales with Dynamic Type, and each line
/// is one VoiceOver element ("Upper edge, 140 mmHg, Blutdruck-Grenze").
struct ReferenceLineMarks: ChartContent {
    /// Already in the unit the chart plots in (``ChartDetailStore/plotReferenceLines(units:)``).
    let lines: [SeriesReferenceLine]
    /// The axis unit, spoken after the value.
    let unit: String

    /// Nothing to draw: every chart without server lines.
    static let none = ReferenceLineMarks(lines: [], unit: "")

    var body: some ChartContent {
        ForEach(lines) { line in
            let style = ReferenceLineStyle(line: line)
            RuleMark(y: .value(line.label, line.value))
                .foregroundStyle(style.tint)
                .lineStyle(StrokeStyle(
                    lineWidth: HLChartGrid.thresholdWidth,
                    dash: style.isDashed ? HLChartGrid.thresholdDash : []
                ))
                .annotation(position: .top, alignment: .leading, spacing: HLSpace.xxs) {
                    Text(line.label)
                        .font(.hlCaption2)
                        .foregroundStyle(HLText.secondary)
                        .lineLimit(1)
                }
                .accessibilityLabel(Text(style.accessibilityLabel))
                .accessibilityValue(Text(style.accessibilityValue(unit: unit)))
        }
    }
}

/// The pure half of a reference line's look and speech, so the mapping is
/// testable without a chart host.
struct ReferenceLineStyle: Equatable {
    enum TintRole: Equatable {
        case upper
        case lower
        case neutral
    }

    let line: SeriesReferenceLine

    var tintRole: TintRole {
        switch line.kind {
        case .upper: .upper
        case .lower: .lower
        case .unknown: .neutral
        }
    }

    var tint: Color {
        switch tintRole {
        case .upper: HLChartTints.thresholdHigh
        case .lower: HLChartTints.thresholdLow
        case .neutral: HLText.tertiary
        }
    }

    /// Clinical (and any source this build does not know) dashed; a line the
    /// person set themselves solid.
    var isDashed: Bool {
        line.source != .personal
    }

    var accessibilityLabel: String {
        switch line.kind {
        case .upper: AppLocale.string("chart.referenceLine.a11y.upper")
        case .lower: AppLocale.string("chart.referenceLine.a11y.lower")
        case .unknown: AppLocale.string("chart.referenceLine.a11y.line")
        }
    }

    func accessibilityValue(unit: String) -> String {
        let number = line.value.formatted(.number.precision(.fractionLength(0 ... 1)))
        let value = unit.isEmpty ? number : "\(number) \(unit)"
        return line.label.isEmpty ? value : "\(value), \(line.label)"
    }
}

extension MetricChartContent {
    /// ``marks(for:points:emphasisTint:includeThresholds:showsPoints:seriesLineWidth:)``
    /// for a detail chart, with the server's reference lines drawn first so the
    /// series paints on top.
    @ChartContentBuilder
    static func marks(
        for kind: MetricKind,
        points: [SeriesPoint],
        emphasisTint: Color?,
        references: ReferenceLineMarks
    ) -> some ChartContent {
        references
        marks(for: kind, points: points, emphasisTint: emphasisTint)
    }
}

extension MetricChartMath {
    /// ``logDomain(for:)`` widened so every reference line is on screen: a
    /// line outside the plotted values would otherwise sit off the chart.
    static func logDomain(for points: [SeriesPoint], including lines: [SeriesReferenceLine]) -> ClosedRange<Double> {
        let base = logDomain(for: points)
        let values = lines.map(\.value).filter { $0.isFinite && $0 > 0 }
        guard let lo = values.min(), let hi = values.max(), !points.isEmpty else { return base }
        let lower = min(base.lowerBound, lo * 0.95)
        let upper = max(base.upperBound, hi * 1.05)
        return lower ... (upper > lower ? upper : lower + 1)
    }
}

extension ChartDetailStore {
    /// The marks for this chart's server reference lines, in the unit the
    /// chart plots in (empty on an older server).
    func referenceLineMarks(units: UnitPreferences) -> ReferenceLineMarks {
        ReferenceLineMarks(lines: plotReferenceLines(units: units), unit: displayUnit(units: units))
    }
}
