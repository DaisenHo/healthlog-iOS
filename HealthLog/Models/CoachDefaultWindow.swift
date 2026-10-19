import Foundation

/// #126 P2 (server v1.40.2) — `coach-prefs.defaultWindow`: how far back the
/// Coach may read, in every answer (snapshot, retrieval tools and summaries
/// alike). `allTime` (the server default) is no limit; `lastYear` came with
/// the limit. A word this build does not know is kept as `nil` and never
/// written back.
public enum CoachDefaultWindow: String, CaseIterable, Identifiable, Sendable {
    case last7days
    case last30days
    case last90days
    case lastYear
    case allTime

    public var id: String {
        rawValue
    }

    public var labelKey: String {
        switch self {
        case .last7days: "settings.coach.window.last7days"
        case .last30days: "settings.coach.window.last30days"
        case .last90days: "settings.coach.window.last90days"
        case .lastYear: "settings.coach.window.lastYear"
        case .allTime: "settings.coach.window.allTime"
        }
    }

    /// The stored window, `.allTime` when the key is absent (the server's
    /// default), `nil` for a word this build does not know.
    public static func from(_ raw: [String: HLJSONValue]) -> CoachDefaultWindow? {
        guard let value = raw["defaultWindow"] else { return .allTime }
        if case let .string(text) = value { return CoachDefaultWindow(rawValue: text) }
        return value == .null ? .allTime : nil
    }

    /// `raw` with only `defaultWindow` changed; every sibling kept.
    public func applied(to raw: [String: HLJSONValue]) -> [String: HLJSONValue] {
        var raw = raw
        raw["defaultWindow"] = .string(rawValue)
        return raw
    }
}
