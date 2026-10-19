import Foundation

/// #136 (server v1.43, #116 item 6) — one mood pattern the server found and
/// published on `GET /api/mood/insights` (`patterns[]`, `MoodPattern` in
/// `docs/api/openapi.yaml` at `v1.43.0`).
///
/// Every entry already passed the server's gate (at least eight days on each
/// side, a Welch test, false discovery control) and was computed on the
/// account's mood day over the `?days` window. The app phrases it and does
/// nothing else: it never tests, ranks, filters by strength or computes a
/// pattern on the device (1.1.0 removed the device-calendar detector for
/// exactly that reason).
///
/// Decoded tolerantly: a `kind`, `strength` or `direction` this build does not
/// know lands on `unknown`, and the presentation skips an entry it cannot
/// phrase. A row that cannot be read at all is dropped on its own.
public struct MoodPattern: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, Equatable, TolerantServerEnum {
        case previousDay = "previous_day"
        case weekend
        case bestWeekday = "best_weekday"
        case notes
        case delayedTag = "delayed_tag"
        case multipleEntries = "multiple_entries"
        case unknown

        public static let unknownFallback = Kind.unknown
        public static let wireVocabulary: StaticString = "mood pattern kind"
    }

    public enum Strength: String, Codable, Sendable, Equatable, TolerantServerEnum {
        case weak
        case moderate
        case strong
        case unknown

        public static let unknownFallback = Strength.unknown
        public static let wireVocabulary: StaticString = "mood pattern strength"
    }

    public enum Direction: String, Codable, Sendable, Equatable, TolerantServerEnum {
        case higher
        case lower
        case none
        case unknown

        public static let unknownFallback = Direction.unknown
        public static let wireVocabulary: StaticString = "mood pattern direction"
    }

    /// The two daily-mean averages the pattern compares, on the account's mood
    /// scale, plus what names the subject.
    public struct Values: Codable, Sendable, Equatable {
        public let subject: Double
        public let comparison: Double
        public let delta: Double
        /// `best_weekday` only: 0 = Monday … 6 = Sunday.
        public let weekday: Int?
        /// `delayed_tag` only.
        public let tagKey: String?
        /// `delayed_tag` only, in the account's language (custom label first).
        public let tagLabel: String?

        public init(
            subject: Double,
            comparison: Double,
            delta: Double,
            weekday: Int? = nil,
            tagKey: String? = nil,
            tagLabel: String? = nil
        ) {
            self.subject = subject
            self.comparison = comparison
            self.delta = delta
            self.weekday = weekday
            self.tagKey = tagKey
            self.tagLabel = tagLabel
        }
    }

    /// Days on each side of the comparison: the "based on N days" line.
    public struct SampleSize: Codable, Sendable, Equatable {
        public let subject: Int
        public let comparison: Int

        public init(subject: Int, comparison: Int) {
            self.subject = subject
            self.comparison = comparison
        }
    }

    /// Stable: `previous_day`, `weekend`, `best_weekday`, `notes`,
    /// `multiple_entries` or `delayed_tag:<tagKey>`.
    public let id: String
    public let kind: Kind
    public let strength: Strength
    public let direction: Direction
    public let values: Values
    public let sampleSize: SampleSize

    public init(
        id: String,
        kind: Kind,
        strength: Strength,
        direction: Direction,
        values: Values,
        sampleSize: SampleSize
    ) {
        self.id = id
        self.kind = kind
        self.strength = strength
        self.direction = direction
        self.values = values
        self.sampleSize = sampleSize
    }

    /// Decodes `patterns` row by row, keeping the server's order. `nil` when
    /// the field is absent (a server before v1.43: the cards stay hidden),
    /// `[]` when the server found none.
    static func decodeList<K: CodingKey>(from c: KeyedDecodingContainer<K>, forKey key: K) -> [MoodPattern]? {
        guard c.contains(key), (try? c.decodeNil(forKey: key)) == false,
              let rows = try? c.decode([Lossy].self, forKey: key) else { return nil }
        return rows.compactMap(\.pattern)
    }

    private struct Lossy: Decodable {
        let pattern: MoodPattern?

        init(from decoder: Decoder) throws {
            pattern = try? MoodPattern(from: decoder)
        }
    }
}
