import Foundation
@testable import HealthLog
import Testing

// swiftlint:disable force_unwrapping

/// INT-Q (1.3, X2 #136 with X3 #126 P2) — since v1.43 the server cuts both
/// `stability` and `patterns` of `GET /api/mood/insights` to the `?days`
/// window (`src/app/api/mood/insights/route.ts` at `2f5c4659f`). Each window
/// therefore has its own SWR row: a 30-day view must never paint the year's
/// patterns from the `.moodInsights` row, and a mood write drops every row.
@MainActor
@Suite("INT-Q — mood insights cache one row per ?days window", .serialized, .mockURLSession)
struct MoodInsightsWindowCacheTests {
    private nonisolated static func body(window: Int, patternID: String) -> Data {
        Data(#"""
        {"data":{"betterDays":[],"stability":{"score":50,"stdDev":0.5,"band":"steady","days":20},
        "stabilityWindowDays":\#(window),
        "patterns":[{"id":"\#(patternID)","kind":"weekend","strength":"strong","direction":"higher",
        "values":{"subject":7.4,"comparison":6.1,"delta":1.3},"sampleSize":{"subject":30,"comparison":74}}]},
        "error":null}
        """#.utf8)
    }

    private final class StubReach: ReachabilityProviding, @unchecked Sendable {
        var isOnlineStream: AsyncStream<Bool> {
            get async { AsyncStream { c in c.yield(true)
                c.finish()
            } }
        }

        func isCurrentlyOnline() async -> Bool {
            true
        }

        func confirmedReachable() async -> Bool {
            true
        }
    }

    private func makeRepo(swr: SWRCoordinator) -> MoodRelationsRepository {
        let env = AppEnvironment(
            baseURL: URL(string: "https://test.healthlog.local")!,
            bundleID: "dev.healthlog.app",
            appVersion: "1.3.0",
            buildNumber: "1"
        )
        let kc = InMemoryKeychain()
        try? kc.setString("token", forKey: KeychainKey.authToken)
        let api = APIClient(environment: env, keychain: kc, sessionConfiguration: .mock())
        return MoodRelationsRepository(api: api, swr: swr)
    }

    @Test("A 30-day view shows the 30-day patterns, and each window is its own cache row")
    func windowsDoNotShareARow() async throws {
        let seen = WindowQueryLog()
        MockURLProtocol.install { req in
            let query = req.url?.query ?? ""
            seen.append(query)
            let body = query.contains("days=30")
                ? Self.body(window: 30, patternID: "month")
                : Self.body(window: 365, patternID: "year")
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let cache = try SWRCache(modelContainer: SWRCache.makeInMemory())
        let swr = SWRCoordinator(cache: cache, reachability: StubReach())
        let repo = makeRepo(swr: swr)

        let store = MoodRelationsStore(repo: repo)
        await store.load()
        #expect(store.patterns(forDays: 30) == nil, "the year's answer is not the 30-day answer")
        await store.loadStability(days: 30)
        // The write-through persists on a detached utility task; drain it so
        // the second page reads the rows instead of racing the writes.
        await swr.drainPendingWrites()
        #expect(store.patterns(forDays: 30)?.map(\.id) == ["month"])
        #expect(store.patterns(forDays: 365)?.map(\.id) == ["year"])
        #expect(seen.all == ["", "days=30"])

        // A second page in the same session paints both from their own rows.
        let again = MoodRelationsStore(repo: repo)
        await again.load()
        await again.loadStability(days: 30)
        #expect(again.patterns(forDays: 30)?.map(\.id) == ["month"])
        #expect(again.patterns(forDays: 365)?.map(\.id) == ["year"])
        #expect(seen.all == ["", "days=30"], "both served from the cache, no extra request")

        let month: Cached<MoodRelationsResponse>? = await cache.read(.moodInsightsWindow(days: 30), as: MoodRelationsResponse.self)
        let year: Cached<MoodRelationsResponse>? = await cache.read(.moodInsights, as: MoodRelationsResponse.self)
        #expect(month?.value.stabilityWindowDays == 30)
        #expect(year?.value.stabilityWindowDays == 365)
    }

    @Test("The window keys are distinct and a mood write drops every one of them")
    func keysAndInvalidation() {
        let keys = [CacheKey.moodInsights] + [30, 90, 180, 365].map { CacheKey.moodInsightsWindow(days: $0) }
        #expect(Set(keys.map(\.persistentHash)).count == keys.count)
        let dropped = MutationKind.moodEntryChange.affectedKeys(profileTimeZone: .current, now: Date())
        for key in keys {
            #expect(dropped.contains(key), "a mood write must drop \(key.canonicalString)")
        }
    }

    @Test("An older server without stabilityWindowDays keeps its one pattern list for every period")
    func olderServerKeepsItsList() async throws {
        MockURLProtocol.install { req in
            let body = Data(#"{"data":{"betterDays":[],"patterns":[]},"error":null}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let cache = try SWRCache(modelContainer: SWRCache.makeInMemory())
        let store = MoodRelationsStore(repo: makeRepo(swr: SWRCoordinator(cache: cache, reachability: StubReach())))
        await store.load()
        #expect(store.response?.stabilityWindowDays == nil)
        #expect(store.patterns(forDays: 30) == [])
        #expect(store.patterns(forDays: 365) == [])
    }
}

private final class WindowQueryLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func append(_ query: String) {
        lock.withLock { entries.append(query) }
    }

    var all: [String] {
        lock.withLock { entries }
    }
}
