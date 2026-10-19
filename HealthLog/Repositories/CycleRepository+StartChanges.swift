import Foundation

/// #137 (server v1.43) — the cycle DELETEs ask for what they changed.
extension CycleRepository {
    /// A cycle DELETE that asks for its outcome (`Prefer: return=representation`,
    /// RFC 7240). The raw body is read because the answer is either an empty
    /// 204 (an older server, or one that ignores the preference) or a 200
    /// envelope with ``CycleDeleteOutcome``; both are a successful delete.
    func deleteReportingStarts(_ path: String, idempotencyKey: IdempotencyKey) async throws -> CycleDeleteOutcome {
        let req = APIRequest<Data>(
            method: .delete,
            path: path,
            extraHeaders: ["Prefer": "return=representation"],
            idempotencyKey: idempotencyKey
        )
        let (data, _) = try await api.download(req)
        return CycleDeleteOutcome.decode(data)
    }
}
