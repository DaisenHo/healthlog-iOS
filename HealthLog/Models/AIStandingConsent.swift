import Foundation

// #143 / server v1.43.2 — the standing AI consent as the SERVER resolves it
// (`ai.consent` on `GET /api/auth/me`, schema `AiConsentState`).
//
// The server decides whether consent is needed: only when data would go through
// a credential the operator holds. The app renders from this block and never
// mints a receipt on its own. `POST /api/consent/ai` requires `confirm: true`
// since v1.43.2 and is sent only from the person's Accept tap.
//
// A server before v1.43.2 sends no `consent` inside the `ai` block; the block is
// then `nil` and the older behaviour applies (minus any silent minting).

/// `ai.consent.status` (server `AiConsentState.status`).
public enum AIConsentStatus: String, Sendable, Equatable, TolerantServerEnum {
    /// An `ai_full` receipt is active (`since` says when).
    case given
    /// The provider chain runs through an operator-held credential and a
    /// capability is closed by the missing receipt alone: ask, naming
    /// `recipients`, and grant only from the person's tap.
    case needed
    /// Nothing to ask and nothing to withdraw (own key, own ChatGPT account,
    /// local model, on-device).
    case notNeeded = "not_needed"
    /// Decode-only sentinel for a status this build does not know. Treated as
    /// "no verdict": the older behaviour applies and nothing is minted.
    case unknown = "__UNKNOWN__"

    public static let unknownFallback = AIConsentStatus.unknown
    public static let wireVocabulary: StaticString = "AI consent status"
}

/// How an operator-held recipient is reached (`recipients[].via`).
public enum AIConsentRecipientVia: String, Sendable, Equatable, Hashable, TolerantServerEnum {
    /// The operator's API key.
    case operatorKey = "operator_key"
    /// The operator's shared ChatGPT account.
    case operatorChatGPT = "operator_chatgpt"
    case unknown = "__UNKNOWN__"

    public static let unknownFallback = AIConsentRecipientVia.unknown
    public static let wireVocabulary: StaticString = "AI consent recipient via"
}

/// One operator-held service the data goes to, named for a person by the
/// server (`OpenAI`, `Anthropic`, `ChatGPT (OpenAI)` or an endpoint host).
public struct AIConsentRecipient: Sendable, Equatable, Hashable {
    public let via: AIConsentRecipientVia
    public let name: String

    public init(via: AIConsentRecipientVia, name: String) {
        self.via = via
        self.name = name
    }
}

/// The `ai.consent` block (server `AiConsentState`, v1.43.2).
public struct AIStandingConsent: Decodable, Sendable, Equatable {
    public let status: AIConsentStatus
    /// When the active `ai_full` consent was given; `nil` unless `given`.
    public let since: Date?
    /// The operator-held services in chain order. Empty when the chain holds none.
    public let recipients: [AIConsentRecipient]

    public init(status: AIConsentStatus, since: Date? = nil, recipients: [AIConsentRecipient] = []) {
        self.status = status
        self.since = since
        self.recipients = recipients
    }

    private enum CodingKeys: String, CodingKey {
        case status, since, recipients
    }

    private struct WireRecipient: Decodable {
        let via: String?
        let name: String?
    }

    /// Tolerant: an unreadable `status` fails the block (the caller then reads
    /// it as absent, the older behaviour); an unknown status lands on
    /// ``AIConsentStatus/unknown``. `since` that does not parse is `nil`. A
    /// recipient without a readable name is skipped, never the whole list.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(AIConsentStatus.self, forKey: .status)
        since = (try? c.decodeIfPresent(String.self, forKey: .since)).flatMap(Self.parseInstant)
        let wire = (try? c.decodeIfPresent([LossyRecipient].self, forKey: .recipients)) ?? []
        recipients = wire.compactMap { entry in
            guard let row = entry.row,
                  let name = row.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return nil }
            return AIConsentRecipient(via: AIConsentRecipientVia(wireValue: row.via ?? ""), name: name)
        }
    }

    /// One recipient row that may fail to decode on its own.
    private struct LossyRecipient: Decodable {
        let row: WireRecipient?
        init(from decoder: Decoder) throws {
            row = try? WireRecipient(from: decoder)
        }
    }

    /// The status the app acts on: `nil` when the server gave no verdict this
    /// build understands.
    public var verdict: AIConsentStatus? {
        status == .unknown ? nil : status
    }

    /// The recipient names in chain order, each once.
    public var recipientNames: [String] {
        var seen = Set<String>()
        return recipients.map(\.name).filter { seen.insert($0).inserted }
    }

    private static func parseInstant(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}
