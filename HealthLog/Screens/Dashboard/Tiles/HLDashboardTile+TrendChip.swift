import SwiftUI

// MARK: - Trend chip

/// Inline trend glyph — arrow only, no background fill.
///
/// Split out of `HLDashboardTile.swift` (v0.16 Build 7 / item 7.1) so that file
/// stays under the `file_length` budget after the 7-/30-day-average additions.
///
/// **Theme C-5 (2026-05-16, R1-Strategy-C + R2 Primitive-#3):** flattened
/// from a filled-circle pill (`color.opacity(0.18)` background, padded
/// arrow) to a flat inline glyph. Driver: the operator's design
/// philosophy ("cool/schlicht/minimalistisch, nicht so Akzentfarben, keine
/// Gamification, Withings-Reference") plus the cross-dashboard load of
/// 8+ tinted pills painting the grid as visual noise (R5 felt-UX audit).
///
/// Colour rules:
/// - **Adverse trend** (up on `lowerIsBetter` / down on `higherIsBetter`)
///   → `statusBad` (Dracula-red) — the only retained colour, per R5 a11y
///   mitigation so trend direction stays legible to non-colour-aware
///   users without leaning on green/red duality.
/// - **Favorable + flat + neutral trend** → `textSecondary` — monochrome,
///   reads as "trend present but not alarming".
/// - **Unknown trend** → render nothing (`EmptyView`). Empty-state tiles
///   no longer show a `?` chip — silence is the calmer signal.
///
/// Apple Health Summary tiles + Withings Health Mate both render the
/// trend the same way: arrow inline, no filled background. See R2
/// Primitive-#3 spec (lines 442-469).
///
/// `TrendIndicator` carries direction-only — no numeric delta — so the
/// chip is glyph-only for now. The R2-spec'd `↑ +1.2%` inline delta-text
/// is deferred until the model gains a `delta` field (out of scope for
/// C-5 per the file-disjoint contract).
struct TrendChip: View {
    enum Mode: Sendable, Equatable {
        /// Existing clinical presentation: only adverse movement is red.
        case polarityAware
        /// Dashboard-only literal presentation requested by the operator.
        case dashboardDirection
        /// #115 · 1.1 — the server's own verdict on which way is progress
        /// (weight: `tiles.weightTrend.direction`). Colour comes from
        /// ``TrendDirectionSentiment/tone(for:)`` and nothing else; `nil`
        /// (no snapshot yet, offline) colours nothing.
        case serverSentiment(TrendDirectionSentiment?)
        /// #135 (server v1.43) — the server's verdict already applied to this
        /// card's own change (`trendSentiment`): positive green, negative red,
        /// neutral monochrome. Nothing is looked up or derived.
        case serverVerdict(TrendSentiment)
    }

    enum ColorRole: String, Sendable {
        case statusOK
        case statusBad
        case textSecondary
        case none
    }

    let trend: TrendIndicator
    let polarity: MetricKindDescriptor.TrendPolarity
    let mode: Mode

    init(
        trend: TrendIndicator,
        polarity: MetricKindDescriptor.TrendPolarity,
        mode: Mode = .polarityAware
    ) {
        self.trend = trend
        self.polarity = polarity
        self.mode = mode
    }

    var body: some View {
        if let symbolName {
            Image(systemName: symbolName)
                // swiftlint:disable:next dynamic_type_bypass
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(foregroundColor)
                .accessibilityHidden(true) // surfaced via the parent label
        }
    }

    /// `nil` → render nothing (unknown trends suppress the chip entirely).
    private var symbolName: String? {
        switch trend {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .flat: "minus"
        case .unknown: nil
        }
    }

    /// Adverse for the metric's polarity (up on `lowerIsBetter` / down on
    /// `higherIsBetter`) → `statusBad`. Everything else is monochrome — the
    /// legacy `statusOK` (green) branch is gone so the grid no longer
    /// alternates green/red across tiles (Theme-2.0 T2-2 / C-5).
    var isAdverse: Bool {
        switch (trend, polarity) {
        case (.up, .lowerIsBetter), (.down, .higherIsBetter):
            true
        default:
            false
        }
    }

    var colorRole: ColorRole {
        guard trend != .unknown else { return .none }
        switch mode {
        case .polarityAware:
            return isAdverse ? .statusBad : .textSecondary
        case .dashboardDirection:
            switch trend {
            case .up: return .statusOK
            case .down: return .statusBad
            case .flat: return .textSecondary
            case .unknown: return .none
            }
        case let .serverSentiment(sentiment):
            guard let sentiment, let change = Self.change(for: trend) else { return .textSecondary }
            switch sentiment.tone(for: change) {
            case .favorable: return .statusOK
            case .adverse: return .statusBad
            case .neutral: return .textSecondary
            }
        case let .serverVerdict(verdict):
            return Self.colorRole(for: verdict)
        }
    }

    /// The colour a delivered verdict paints; an unknown word paints nothing.
    static func colorRole(for verdict: TrendSentiment) -> ColorRole {
        switch verdict {
        case .positive: .statusOK
        case .negative: .statusBad
        case .neutral, .unknown: .textSecondary
        }
    }

    /// The observed direction in the sentiment table's vocabulary.
    static func change(for trend: TrendIndicator) -> TrendDirectionSentiment.Change? {
        switch trend {
        case .up: .rising
        case .down: .falling
        case .flat: .level
        case .unknown: nil
        }
    }

    private var foregroundColor: Color {
        switch colorRole {
        case .statusOK: HLColor.statusOK
        case .statusBad: HLColor.statusBad
        case .textSecondary, .none: HLText.secondary
        }
    }
}

extension DashboardMetric {
    /// Direction shown by dashboard surfaces: the server's, as sent. Without
    /// one the tile shows no arrow. Steps and sleep used to derive a direction
    /// from the first and last sparkline point (weight until #115 · 1.1); that
    /// guess is gone since #115 B7.
    var dashboardTrend: TrendIndicator {
        trend
    }

    /// #115 · 1.1 — weight is coloured by the server's target-aware verdict
    /// (`tiles.weightTrend`), never by a client rule. Literal green/up and
    /// red/down stays scoped to steps and sleep; every other kind keeps the
    /// established polarity-aware mode.
    ///
    /// #135 — a v1.43 server sends the verdict for every card
    /// (`trendSentiment`); it wins over every client rule above. Older
    /// servers keep the rendering they always had.
    func dashboardTrendMode(weightSentiment: TrendDirectionSentiment?) -> TrendChip.Mode {
        if let trendSentiment, trendSentiment != .unknown { return .serverVerdict(trendSentiment) }
        if kind == .weight { return .serverSentiment(weightSentiment) }
        return [.steps, .sleep].contains(kind) ? .dashboardDirection : .polarityAware
    }

    /// #135 — VoiceOver hears the server's verdict next to the direction
    /// ("Trend rising, a good direction for you"). Empty without one.
    var spokenVerdictSuffix: String {
        guard let clause = trendSentiment?.spokenClause else { return "" }
        return ", \(clause)"
    }

    /// The spoken direction plus the server's verdict, for surfaces whose
    /// label did not speak a trend before v1.43. `nil` without a verdict (an
    /// older server keeps its label) or without a known direction.
    var spokenTrendWithVerdict: String? {
        guard trendSentiment != nil else { return nil }
        let direction: String? = switch trend {
        case .up: AppLocale.string("Trend rising")
        case .down: AppLocale.string("Trend falling")
        case .flat: AppLocale.string("Trend stable")
        case .unknown: nil
        }
        return direction.map { $0 + spokenVerdictSuffix }
    }

    /// The chip mode for a surface outside the dashboard grid: the server's
    /// verdict when it sends one, else the established polarity-aware mode.
    var verdictOrPolarityMode: TrendChip.Mode {
        guard let trendSentiment, trendSentiment != .unknown else { return .polarityAware }
        return .serverVerdict(trendSentiment)
    }
}
