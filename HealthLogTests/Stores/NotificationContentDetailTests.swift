import Foundation
@testable import HealthLog
import Testing

// swiftlint:disable force_unwrapping

/// #126 3.3 (server v1.42.2) — `notificationPrefs.content.detail`: `generic`
/// (default) or `detailed`, read from and written to
/// `/api/auth/me/notification-prefs`. Fixtures per `NotificationPrefs` /
/// `NotificationPrefsPatchRequest` in `docs/api/openapi.yaml` on
/// `release/v1.43.0` (`d06ce3604`).
@MainActor
@Suite("Notification content setting (#126 3.3)", .serialized, .mockURLSession)
struct NotificationContentDetailTests {
    private final class Bodies: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []

        func append(_ request: URLRequest) {
            let data = request.httpBody ?? request.httpBodyStream.map { stream -> Data in
                stream.open()
                defer { stream.close() }
                var out = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    out.append(buffer, count: count)
                }
                return out
            }
            lock.withLock { items.append(data.flatMap { String(data: $0, encoding: .utf8) } ?? "") }
        }

        var all: [String] {
            lock.withLock { items }
        }
    }

    private func makeRepo() -> NotificationsRepository {
        let env = AppEnvironment(
            baseURL: URL(string: "https://test.healthlog.local")!,
            bundleID: "dev.healthlog.app",
            appVersion: "1.3.0",
            buildNumber: "1"
        )
        let kc = InMemoryKeychain()
        try? kc.setString("token", forKey: KeychainKey.authToken)
        return NotificationsRepository(api: APIClient(environment: env, keychain: kc, sessionConfiguration: .mock()))
    }

    @Test("content.detail decodes; absent means the setting is hidden, an unknown word reads generic")
    func decodes() throws {
        func payload(_ json: String) throws -> AuthNotificationPrefsPayload {
            try JSONDecoder.hlDefault.decode(AuthNotificationPrefsPayload.self, from: Data(json.utf8))
        }
        #expect(try payload(#"{"mood":{"reminderHour":22},"content":{"detail":"detailed"}}"#).contentDetailed == true)
        #expect(try payload(#"{"mood":{"reminderHour":22},"content":{"detail":"generic"}}"#).contentDetailed == false)
        #expect(try payload(#"{"mood":{"reminderHour":22},"content":{"detail":"poetic"}}"#).contentDetailed == false)
        #expect(try payload(#"{"mood":{"reminderHour":22}}"#).contentDetailed == nil)
    }

    @Test("Switching it on PATCHes content.detail and renders the server's answer")
    func patchesAndRenders() async {
        let bodies = Bodies()
        MockURLProtocol.install { req in
            bodies.append(req)
            let body = Data(#"""
            {"data":{"mood":{"reminderHour":22},"content":{"detail":"detailed"},"updatedAt":"2026-10-16T08:00:00.000Z"},"error":null}
            """#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let store = NotificationsStore(repo: makeRepo())
        #expect(store.notificationContentDetailed == nil)
        await store.setNotificationContentDetailed(true)
        #expect(store.notificationContentDetailed == true)
        let sent = bodies.all.last ?? ""
        let json = try? JSONSerialization.jsonObject(with: Data(sent.utf8)) as? [String: Any]
        #expect((json?["content"] as? [String: String])?["detail"] == "detailed")
        #expect(json?["mood"] == nil, "only the one leaf is written; the server deep-merges")
    }

    @Test("A failed write puts the previous value back")
    func failureRollsBack() async {
        MockURLProtocol.install { req in
            let body = Data(#"{"data":null,"error":"Invalid","meta":{"errorCode":"notification_prefs.invalid"}}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 422, httpVersion: nil, headerFields: nil)!, body)
        }
        let store = NotificationsStore(repo: makeRepo())
        await store.setNotificationContentDetailed(true)
        #expect(store.notificationContentDetailed == nil)
        #expect(store.error != nil)
    }
}
