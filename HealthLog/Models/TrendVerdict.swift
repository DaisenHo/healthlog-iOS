import Foundation

// MARK: - Direction verdicts (#135, server v1.43)

/// Which way a change of a metric counts as progress for this person, judged
/// by the server against the person's own target band, a profile default (for
/// example the age-based blood pressure target) or the metric's default.
///
/// Wire: `TrendVerdict` in `docs/api/openapi.yaml` at `v1.43.0`, carried by
/// `GET /api/measurements/series` (`direction`), `GET /api/dashboard/summary`
/// (`metrics[].direction`), `GET /api/insights/targets` (`targets[].direction`)
/// and the snapshot's `tiles.directions`. The generalisation of
/// `tiles.weightTrend` (``WeightTrendJudgement``). The app renders it and
/// never derives one of its own.
///
/// Every word is decoded tolerantly: a direction this build does not know
/// lands on ``TrendDirectionSentiment/unknown`` and colours nothing.
public struct TrendVerdict: Codable, Sendable, Hashable {
    /// What the verdict was judged against.
    public enum Basis: String, Codable, Sendable, Hashable, TolerantServerEnum {
        case personalTarget = "personal_target"
        case profileDefault = "profile_default"
        case metricDefault = "metric_default"
        /// A basis word this build does not know.
        case unknown

        public static let unknownFallback = Basis.unknown
        public static let wireVocabulary: StaticString = "trend verdict basis"
    }

    public let direction: TrendDirectionSentiment
    /// Where the value sits against the band; `nil` without one.
    public let targetPosition: WeightTrendJudgement.TargetPosition?
    public let basis: Basis

    public init(
        direction: TrendDirectionSentiment,
        targetPosition: WeightTrendJudgement.TargetPosition? = nil,
        basis: Basis = .metricDefault
    ) {
        self.direction = direction
        self.targetPosition = targetPosition
        self.basis = basis
    }

    private enum CodingKeys: String, CodingKey {
        case direction, targetPosition, basis
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        direction = (try? c.decode(TrendDirectionSentiment.self, forKey: .direction)) ?? .unknown
        targetPosition = try? c.decodeIfPresent(WeightTrendJudgement.TargetPosition.self, forKey: .targetPosition)
        basis = (try? c.decode(Basis.self, forKey: .basis)) ?? .unknown
    }
}

/// The verdict applied to one delivered change, with the server's noise floor
/// applied (`TrendSentiment`, v1.43). Colour the change from this and nothing
/// else.
public enum TrendSentiment: String, Codable, Sendable, Hashable, CaseIterable, TolerantServerEnum {
    case positive
    case negative
    case neutral
    /// A sentiment word this build does not know: rendered like `neutral`.
    case unknown

    public static let unknownFallback = TrendSentiment.unknown
    public static let wireVocabulary: StaticString = "trend sentiment"

    /// The spoken half of the colour, so VoiceOver hears what the tint shows.
    /// `nil` for a neutral or unknown verdict: nothing to add.
    public var spokenClause: String? {
        switch self {
        case .positive: String(localized: "trend.verdict.spoken.positive")
        case .negative: String(localized: "trend.verdict.spoken.negative")
        case .neutral, .unknown: nil
        }
    }
}

/// First and last day value of a series window and how that change counts
/// (`SeriesChange`, v1.43). `nil` on the series under two days.
public struct SeriesChange: Codable, Sendable, Hashable {
    public let from: Double
    public let to: Double
    public let delta: Double
    public let sentiment: TrendSentiment

    public init(from: Double, to: Double, delta: Double, sentiment: TrendSentiment) {
        self.from = from
        self.to = to
        self.delta = delta
        self.sentiment = sentiment
    }
}

// MARK: - Chart reference lines (#135, server v1.43)

/// A horizontal line the server asks the chart to draw
/// (`SeriesReferenceLine`, v1.43), in the unit of the series response. A
/// personal line has already replaced the clinical one for the same edge on
/// the server; the app draws the list as delivered.
public struct SeriesReferenceLine: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable, TolerantServerEnum {
        case lower
        case upper
        case unknown

        public static let unknownFallback = Kind.unknown
        public static let wireVocabulary: StaticString = "reference line kind"
    }

    public enum Source: String, Codable, Sendable, Hashable, TolerantServerEnum {
        case personal
        case clinical
        case unknown

        public static let unknownFallback = Source.unknown
        public static let wireVocabulary: StaticString = "reference line source"
    }

    public enum AppliesTo: String, Codable, Sendable, Hashable, TolerantServerEnum {
        case value
        /// The diastolic value of a blood pressure.
        case secondary
        case unknown

        public static let unknownFallback = AppliesTo.unknown
        public static let wireVocabulary: StaticString = "reference line target"
    }

    public let value: Double
    public let kind: Kind
    public let source: Source
    public let appliesTo: AppliesTo
    public let labelKey: String
    /// Already in the account's language.
    public let label: String

    public var id: String {
        "\(appliesTo.rawValue).\(kind.rawValue).\(labelKey).\(value)"
    }

    public init(
        value: Double,
        kind: Kind,
        source: Source,
        appliesTo: AppliesTo = .value,
        labelKey: String = "",
        label: String
    ) {
        self.value = value
        self.kind = kind
        self.source = source
        self.appliesTo = appliesTo
        self.labelKey = labelKey
        self.label = label
    }

    /// The same line moved to another value (the account's display unit).
    public func withValue(_ newValue: Double) -> SeriesReferenceLine {
        SeriesReferenceLine(
            value: newValue,
            kind: kind,
            source: source,
            appliesTo: appliesTo,
            labelKey: labelKey,
            label: label
        )
    }

    /// Decodes a `referenceLines` array row by row: a row this build cannot
    /// read (a non-finite value, a missing field) is dropped on its own, never
    /// the whole series. `nil` when the field is absent (a server before
    /// v1.43), `[]` when the server has nothing to draw.
    static func decodeList<K: CodingKey>(from c: KeyedDecodingContainer<K>, forKey key: K) -> [SeriesReferenceLine]? {
        guard c.contains(key), (try? c.decodeNil(forKey: key)) == false,
              let rows = try? c.decode([Lossy].self, forKey: key) else { return nil }
        return rows.compactMap(\.line).filter(\.value.isFinite)
    }

    private struct Lossy: Decodable {
        let line: SeriesReferenceLine?

        init(from decoder: Decoder) throws {
            line = try? SeriesReferenceLine(from: decoder)
        }
    }
}

// MARK: - Record benchmarks (#135, server v1.43)

/// An age- and sex-aware comparison band from a cited norm, in the record's
/// unit (`RecordBenchmark` on `GET /api/personal-records`, v1.43). `nil` on a
/// record without a cited norm and on every server before v1.43.
public struct RecordBenchmark: Codable, Sendable, Hashable {
    public let low: Double
    public let high: Double
    public let unit: String
    public let source: String
    /// Already in the account's language.
    public let sourceLabel: String

    public init(low: Double, high: Double, unit: String, source: String, sourceLabel: String) {
        self.low = low
        self.high = high
        self.unit = unit
        self.source = source
        self.sourceLabel = sourceLabel
    }

    /// A band the app can draw: both edges finite and in order.
    public var isDrawable: Bool {
        low.isFinite && high.isFinite && low <= high
    }
}
