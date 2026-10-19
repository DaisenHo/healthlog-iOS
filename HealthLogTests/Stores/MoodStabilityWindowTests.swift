import Foundation
@testable import HealthLog
import Testing

// swiftlint:disable force_unwrapping

/// #126 P2 (server v1.42.0, #116 item 7) — mood stability follows the
/// chosen period: `GET /api/mood/insights?days=` with `stabilityWindowDays`;
/// and (v1.42.2) the history source filter offers `NOTIFICATION`. Fixtures per
/// `MoodAggregates` in `docs/api/openapi.yaml` on `release/v1.43.0`
/// (`d06ce3604`).
@MainActor
@Suite("Mood stability per period and the NOTIFICATION source (#126 P2)", .serialized, .mockURLSession)
struct MoodStabilityWindowTests {
    private nonisolated static func body(days: Int?, score: Int) -> Data {
        let window = days.map { #","stabilityWindowDays":\#($0)"# } ?? ""
        return Data(#"""
        {"data":{"stability":{"score":\#(score),"stdDev":0.5,"band":"steady","days":20}\#(window)},"error":null}
        """#.utf8)
    }

    private func makeStore() -> MoodRelationsStore {
        let env = AppEnvironment(
            baseURL: URL(string: "https://test.healthlog.local")!,
            bundleID: "dev.healthlog.app",
            appVersion: "1.3.0",
            buildNumber: "1"
        )
        let kc = InMemoryKeychain()
        try? kc.setString("token", forKey: KeychainKey.authToken)
        let api = APIClient(environment: env, keychain: kc, sessionConfiguration: .mock())
        return MoodRelationsStore(repo: MoodRelationsRepository(api: api))
    }

    @Test("The page's period is asked as ?days= and only the window the server echoes is shown")
    func stabilityFollowsPeriod() async {
        let seen = QueryLog()
        MockURLProtocol.install { req in
            let query = req.url?.query ?? ""
            seen.append(query)
            let body: Data = if query.contains("days=30") {
                Self.body(days: 30, score: 41)
            } else if query.contains("days=90") {
                Self.body(days: 365, score: 99)
            } else {
                Self.body(days: 365, score: 73)
            }
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let store = makeStore()
        await store.load()
        await store.loadStability(days: 30)
        await store.loadStability(days: 90)
        await store.loadStability(days: 30)
        await store.loadStability(days: 7)
        #expect(seen.all == ["", "days=30", "days=90"])
        #expect(store.stability(forDays: 30)?.score == 41)
        #expect(store.stability(forDays: 90) == nil, "a window the server did not echo is not shown")
        #expect(store.stability(forDays: 365)?.score == 73)
        store.clearOnLogout()
        #expect(store.stabilityByDays.isEmpty)
    }

    @Test("An older server (no stabilityWindowDays) keeps showing its one stability")
    func olderServerUnchanged() throws {
        let old = try JSONDecoder.hlDefault.decode(
            APIEnvelope<MoodRelationsResponse>.self, from: Self.body(days: nil, score: 60)
        ).data
        #expect(old?.stabilityWindowDays == nil)
        let new = try JSONDecoder.hlDefault.decode(
            APIEnvelope<MoodRelationsResponse>.self, from: Self.body(days: 90, score: 60)
        ).data
        #expect(new?.stabilityWindowDays == 90)
    }

    @Test("NOTIFICATION is a history filter source and rides the query")
    func notificationSource() {
        #expect(MoodEntrySource.allCases.contains(.notification))
        let query = MoodHistoryQuery(source: .notification)
        #expect(query.queryItems.contains { $0.0 == "source" && $0.1 == "NOTIFICATION" })
        #expect(!String(localized: "mood.source.notification").isEmpty)
    }
}

private final class QueryLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func append(_ query: String) {
        lock.withLock { entries.append(query) }
    }

    var all: [String] {
        lock.withLock { entries }
    }
}
