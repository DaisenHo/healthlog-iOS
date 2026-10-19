import Foundation

/// **#134 (server v1.43) — the server's id for a failed request.**
///
/// From v1.43 every error envelope carries `meta.requestId`, the same value
/// the server sends in the `x-request-id` response header (that header exists
/// on older servers too). The operator finds the request in the admin log by
/// the first 8 characters, so the app reads the id on a failure, shows its
/// short form and keeps it for "Support-Info kopieren".
///
/// The body wins over the header because a proxy may strip headers; the header
/// is the fallback for servers before v1.43. Both are tolerant: anything that
/// is not the server's own id shape (`^[A-Za-z0-9-]{8,64}$`, the pattern the
/// server itself enforces in `src/lib/http/request-id.ts`) is dropped, so a
/// proxy's or a hostile peer's header can never put free text on screen or
/// on the clipboard. No id at all is a normal answer, not an error.
public enum ServerErrorID {
    /// The response header the server stamps on every request.
    public static let headerName = "x-request-id"

    /// The id the server gave this failed response, or `nil`.
    ///
    /// `meta.requestId` from an error body first, then the header. A 2xx body
    /// (a decoding failure) is never parsed: success payloads do not carry the
    /// field, and a large list body is not worth walking for it.
    public static func extract(from response: HTTPURLResponse, body: Data) -> String? {
        let bodyID = (200 ... 299).contains(response.statusCode) ? nil : fields(in: body).requestId
        return bodyID ?? wellFormed(response.value(forHTTPHeaderField: headerName))
    }

    /// The short form the operator searches for: the first 8 characters.
    public static func short(_ id: String) -> String {
        String(id.prefix(8))
    }

    /// `meta.requestId` and the error code of an error envelope, both
    /// validated. The code is `meta.errorCode`, else the older top-level
    /// `errorCode`, the same precedence `APIClient.ensureSuccess` uses.
    static func fields(in body: Data) -> (requestId: String?, errorCode: String?) {
        guard !body.isEmpty, body.count <= maxEnvelopeBytes,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return (nil, nil) }
        let meta = object["meta"] as? [String: Any]
        let requestId = wellFormed(meta?["requestId"] as? String)
        let code = wellFormedCode(meta?["errorCode"] as? String)
            ?? wellFormedCode(object["errorCode"] as? String)
        return (requestId, code)
    }

    /// The server's id shape: letters, digits and hyphens, 8 to 64 characters.
    static func wellFormed(_ value: String?) -> String? {
        guard let value, (8 ... 64).contains(value.count),
              value.unicodeScalars.allSatisfy({ isASCIIAlphanumeric($0) || $0 == "-" }) else { return nil }
        return value
    }

    /// A machine code from the server's closed list (`medication.notFound`,
    /// `module.disabled`, `assistant.disabled.coach`). Anything with other
    /// characters is prose, not a code, and is dropped.
    static func wellFormedCode(_ value: String?) -> String? {
        guard let value, (1 ... 80).contains(value.count),
              value.unicodeScalars.allSatisfy({ isASCIIAlphanumeric($0) || "._:-".unicodeScalars.contains($0) }) else { return nil }
        return value
    }

    private static func isASCIIAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        ("a" ... "z").contains(scalar) || ("A" ... "Z").contains(scalar) || ("0" ... "9").contains(scalar)
    }

    /// Error envelopes are small; a body larger than this is not one.
    private static let maxEnvelopeBytes = 64 * 1024
}
