import Foundation

/// #135 (server v1.43) — the series route's own verdict and reference lines,
/// read for the metric page. Nothing here judges or places a line: the store
/// hands on what the server sent, converted into the unit the chart plots in.
public extension ChartDetailStore {
    /// The reference lines in the account's unit, the same conversion the
    /// plotted points take (``plotPoints(units:)``): glucose arrives converted
    /// by the server and passes through, a blood pressure in kPa or a weight
    /// in lb converts like a point. Empty on an older server, on a series that
    /// carries none and on a kind this build cannot name.
    func plotReferenceLines(units: UnitPreferences) -> [SeriesReferenceLine] {
        guard !kind.isUnknown, let lines = series?.referenceLines, !lines.isEmpty else { return [] }
        return lines.map { line in
            let converted = kind.unitFamily == nil ? line.value : convertSeriesValue(line.value, units: units)
            return line.withValue(converted)
        }
    }

    /// Which way a change of this metric counts, for the range caption: the
    /// series route's own verdict (v1.43). On an older server only the weight
    /// page has one: the snapshot's `tiles.weightTrend`.
    func rangeDeltaSentiment(weightTrend: WeightTrendJudgement?) -> TrendDirectionSentiment? {
        if let direction = series?.direction?.direction { return direction }
        return kind == .weight ? weightTrend?.direction : nil
    }
}
