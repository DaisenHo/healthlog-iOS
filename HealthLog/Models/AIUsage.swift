import Foundation

// #129 (server v1.43, public #1217) — the account's AI usage level.
//
// The operator sets the highest allowed level and the default, the person picks
// within that. The level decides how often background status cards regenerate,
// the snapshot size, background reasoning, the length of the daily briefing and
// whether automatic document reading and supplement label extraction run. The
// Coach is not affected. The server resolves everything (allowance, estimate,
// the effective level); the app renders `options` and never derives any of it.

/// One of the three levels (server `AiUsageLevel`).
public enum AIUsageLevel: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case frugal
    case standard
    case full
}

/// Where the effective level comes from (server `AiUsageState.source`).
public enum AIUsageSource: String, Sendable, Equatable, TolerantServerEnum {
    /// The person's stored choice.
    case user
    /// The instance default (no stored choice).
    case `default`
    /// The operator's ceiling caps a stored choice above it; the choice is kept.
    case adminCap = "admin_cap"
    case unknown = "__UNKNOWN__"

    public static let unknownFallback = AIUsageSource.unknown
    public static let wireVocabulary: StaticString = "AI usage source"
}

/// One picker option as the server resolved it.
public struct AIUsageOption: Decodable, Sendable, Equatable, Hashable {
    public let level: AIUsageLevel
    /// `level` is at or below the operator's `maxLevel`.
    public let allowed: Bool
    /// The server's estimate for this account at this level; `nil` without
    /// three days of history. Shown as an estimate, never computed here.
    public let estimatedTokensPerDay: Int?

    public init(level: AIUsageLevel, allowed: Bool, estimatedTokensPerDay: Int? = nil) {
        self.level = level
        self.allowed = allowed
        self.estimatedTokensPerDay = estimatedTokensPerDay
    }

    private enum CodingKeys: String, CodingKey {
        case level, allowed, estimatedTokensPerDay
    }

    /// A missing or mistyped `allowed` reads as `false` (fail closed: the
    /// option is shown disabled and never sent).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = try c.decode(AIUsageLevel.self, forKey: .level)
        allowed = (try? c.decodeIfPresent(Bool.self, forKey: .allowed)) ?? false
        estimatedTokensPerDay = try? c.decodeIfPresent(Int.self, forKey: .estimatedTokensPerDay)
    }
}

/// The `ai.usage` block on `GET /api/auth/me` and the answer of
/// `PUT /api/auth/me/ai-usage` (server `AiUsageState`). Absent before v1.43;
/// the setting is then hidden.
public struct AIUsageState: Decodable, Sendable, Equatable {
    /// The level in effect.
    public let level: AIUsageLevel
    /// The stored choice; `nil` follows the server default.
    public let preference: AIUsageLevel?
    public let defaultLevel: AIUsageLevel?
    public let maxLevel: AIUsageLevel?
    public let source: AIUsageSource
    /// Always three on the wire (frugal, standard, full); an option this
    /// build cannot read is dropped, never invented.
    public let options: [AIUsageOption]
    /// Mean tokens per day over the last seven full days; `nil` without history.
    public let measuredTokensPerDay: Int?
    /// How many days stand behind `measuredTokensPerDay` (0 to 7).
    public let measuredDays: Int

    public init(
        level: AIUsageLevel,
        preference: AIUsageLevel? = nil,
        defaultLevel: AIUsageLevel? = nil,
        maxLevel: AIUsageLevel? = nil,
        source: AIUsageSource = .default,
        options: [AIUsageOption],
        measuredTokensPerDay: Int? = nil,
        measuredDays: Int = 0
    ) {
        self.level = level
        self.preference = preference
        self.defaultLevel = defaultLevel
        self.maxLevel = maxLevel
        self.source = source
        self.options = options
        self.measuredTokensPerDay = measuredTokensPerDay
        self.measuredDays = measuredDays
    }

    private enum CodingKeys: String, CodingKey {
        case level, preference, defaultLevel, maxLevel, source, options, measuredTokensPerDay, measuredDays
    }

    /// `level` is required (without it there is nothing to show); every other
    /// field is tolerant, and a malformed option drops only that option.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = try c.decode(AIUsageLevel.self, forKey: .level)
        preference = try? c.decodeIfPresent(AIUsageLevel.self, forKey: .preference)
        defaultLevel = try? c.decodeIfPresent(AIUsageLevel.self, forKey: .defaultLevel)
        maxLevel = try? c.decodeIfPresent(AIUsageLevel.self, forKey: .maxLevel)
        source = (try? c.decodeIfPresent(AIUsageSource.self, forKey: .source)) ?? .unknown
        let rawOptions = (try? c.decodeIfPresent([LossyOption].self, forKey: .options)) ?? []
        options = rawOptions.compactMap(\.value)
        measuredTokensPerDay = try? c.decodeIfPresent(Int.self, forKey: .measuredTokensPerDay)
        measuredDays = (try? c.decodeIfPresent(Int.self, forKey: .measuredDays)) ?? 0
    }

    /// The option for `level`, when the server sent it.
    public func option(_ level: AIUsageLevel) -> AIUsageOption? {
        options.first { $0.level == level }
    }

    /// Whether a PUT for `level` may be sent: only an option the server marked
    /// allowed. A level the server did not list is never sent.
    public func canChoose(_ level: AIUsageLevel) -> Bool {
        option(level)?.allowed == true
    }

    private struct LossyOption: Decodable {
        let value: AIUsageOption?

        init(from decoder: Decoder) throws {
            value = try? AIUsageOption(from: decoder)
        }
    }
}

/// Body of `PUT /api/auth/me/ai-usage`: `{ "level": "frugal" | … | null }`.
/// `nil` is sent as an explicit `null` (follow the server default).
public struct AIUsagePutRequest: Encodable, Sendable, Equatable {
    public let level: AIUsageLevel?

    public init(level: AIUsageLevel?) {
        self.level = level
    }

    private enum CodingKeys: String, CodingKey {
        case level
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let level {
            try c.encode(level, forKey: .level)
        } else {
            try c.encodeNil(forKey: .level)
        }
    }
}
