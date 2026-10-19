import Foundation

public extension SettingsRepository {
    /// #129 (server v1.43) — `PUT /api/auth/me/ai-usage` with
    /// `{ "level": … | null }`. Answers the resolved ``AIUsageState``, which the
    /// caller renders as is. `422 ai.usage.aboveCeiling` (a level above the
    /// operator's ceiling) surfaces as the plain server error; the picker never
    /// sends such a level in the first place.
    func setAIUsage(_ level: AIUsageLevel?) async throws -> AIUsageState {
        let req: APIRequest<AIUsageState> = try .put(
            "/api/auth/me/ai-usage",
            body: AIUsagePutRequest(level: level)
        )
        return try await api.send(req)
    }
}
