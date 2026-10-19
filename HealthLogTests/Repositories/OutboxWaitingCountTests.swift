import Foundation
@testable import HealthLog
import Synchronization
import Testing

/// W1 (1.3.0, #126 1.1, HealthLog#1173) — "6 Einträge warten auf
/// Verbindung" for days while every sync around it succeeded.
///
/// The banner and the `icloud.slash` glyph counted every live outbox row
/// (`SyncStateStore.bindOutbox` took `ops.count`). Rows the replay never sends
/// on its own counted too: parked pages, rows over their retry budget,
/// another account's rows, rows this build cannot attribute. These suites pin
/// that the count asks what the replay asks, that the held rows are listed by
/// reason, and that "Erneut senden" puts them back on the wire.
@Suite("W1 — the waiting count is what the replay can still send")
struct OutboxWaitingCountTests {
    static let owner = "account-w1"

    /// A queue whose signed-in account can be switched off for one enqueue, so
    /// an unowned row (written before the owner stamp existed) can be made.
    /// The signed-in account, switchable between enqueues.
    final class Account: Sendable {
        let signedIn = Mutex<String?>(OutboxWaitingCountTests.owner)
    }

    struct Fixture {
        let queue: OutboxQueue
        let account = Account()

        init() throws {
            let account = account
            queue = try OutboxQueue(inMemory: true, currentOwnerProvider: { account.signedIn.withLock { $0 } })
        }

        @discardableResult
        func row(
            _ key: String,
            attempts: Int = 0,
            owner: String? = OutboxWaitingCountTests.owner,
            lastError: String? = nil
        ) async throws -> UUID {
            let op = OutboxQueue.Operation(
                kind: .createAllergy,
                payload: Data("{}".utf8),
                idempotencyKey: key,
                attempts: attempts,
                ownerUserID: owner
            )
            try await queue.enqueue(op)
            if let lastError { try await queue.touchAttempt(id: op.id, lastError: lastError) }
            return op.id
        }

        /// Three rows the replay sends, six it does not.
        func seedMixedQueue() async throws {
            try await row("plain")
            try await row("backed-off", lastError: "Netzwerk-Fehler: timeout")
            try await row("unconfirmed", attempts: 1, lastError: "unconfirmed:since=1790000000")
            try await row("parked-422", lastError: "parked:not_stored status=422")
            try await row("parked-module", lastError: "parked:module_disabled module=cycle")
            try await row("over-budget", attempts: 8, lastError: "Serverfehler")
            try await row("foreign", owner: "account-other")
            account.signedIn.withLock { $0 = nil }
            try await row("unowned", owner: nil)
            account.signedIn.withLock { $0 = OutboxWaitingCountTests.owner }
            let delivered = try await row("delivered")
            try await queue.markDelivered(id: delivered)
        }
    }

    @Test("only rows the replay sends count as waiting")
    func waitingCountMatchesTheReplayGates() async throws {
        let fixture = try Fixture()
        try await fixture.seedMixedQueue()
        let ops = await fixture.queue.snapshot
        #expect(ops.count == 9, "all nine rows are live in the snapshot")
        #expect(await fixture.queue.waitingCount(in: ops) == 3)
    }

    @Test("held rows are listed by reason, other accounts' rows are not")
    func heldGroupsByReason() async throws {
        let fixture = try Fixture()
        try await fixture.seedMixedQueue()
        let groups = await fixture.queue.heldGroups()
        #expect(Set(groups) == [
            OutboxHeldGroup(reason: .serverRefused(status: 422), count: 1),
            OutboxHeldGroup(reason: .moduleDisabled("cycle"), count: 1),
            OutboxHeldGroup(reason: .retryBudgetExhausted, count: 1)
        ])
    }

    @Test("every park marker the replay writes reads back as its reason")
    func parkMarkersRoundTrip() {
        let cases: [(HealthKitReplayParked.Reason, OutboxHoldReason)] = [
            (.notStored(status: 422), .serverRefused(status: 422)),
            (.moduleDisabled("cycle"), .moduleDisabled("cycle")),
            (.unmappable(count: 3), .unmappable),
            (.refusalNotRecorded, .refusalNotRecorded)
        ]
        for (parked, expected) in cases {
            #expect(OutboxHoldReason(parkedMarker: HealthKitReplayParked(reason: parked).description) == expected)
        }
        #expect(OutboxHoldReason(parkedMarker: "Netzwerk-Fehler: timeout") == nil)
        #expect(OutboxHoldReason(parkedMarker: nil) == nil)
    }

    @Test("Erneut senden puts every held row of the account back on the wire")
    func rearmHeldRows() async throws {
        let fixture = try Fixture()
        try await fixture.seedMixedQueue()

        #expect(try await fixture.queue.rearmHeld() == 3)

        let ops = await fixture.queue.snapshot
        #expect(await fixture.queue.waitingCount(in: ops) == 6)
        #expect(await fixture.queue.heldGroups().isEmpty)
        let overBudget = try #require(ops.first { $0.idempotencyKey == "over-budget" })
        #expect(overBudget.attempts == 0)
        #expect(overBudget.lastError == nil)
        #expect(overBudget.lastAttemptAt == nil)
        let foreign = try #require(ops.first { $0.idempotencyKey == "foreign" })
        #expect(foreign.ownerUserID == "account-other", "another account's row is not touched")
    }

    @Test("a dead-lettered row is not re-armed by Erneut senden")
    func rearmLeavesDeadLettersAlone() async throws {
        let fixture = try Fixture()
        let id = try await fixture.row("dead", attempts: 8, lastError: "parked:not_stored status=422")
        try await fixture.queue.markDeadLetter(id: id, lastError: "refused")
        #expect(try await fixture.queue.rearmHeld() == 0)
        #expect(await fixture.queue.deadLetterCount == 1)
    }
}

// `SyncStateStore` is app-target only.
#if !SWIFT_PACKAGE
    /// The banner and the slot glyph read `pendingOutboxCount`; it must be the
    /// waiting count, not the snapshot size.
    @MainActor
    @Suite("W1 — the banner and the glyph count only waiting rows", .serialized, .mockURLSession)
    struct OutboxWaitingBannerTests {
        private func makeStore() -> SyncStateStore {
            let env = AppEnvironment(
                // swiftlint:disable:next force_unwrapping
                baseURL: URL(string: "https://test.healthlog.local")!,
                bundleID: "dev.healthlog.app",
                appVersion: "1.3.0",
                buildNumber: "1"
            )
            let api = APIClient(environment: env, keychain: InMemoryKeychain(), sessionConfiguration: .mock())
            return SyncStateStore(repo: SyncStateRepository(api: api), minimumSyncingHold: .zero, doneHold: .zero)
        }

        /// Polls the live binding until it reports `expected` or two seconds
        /// pass; returns what it saw last.
        private func settle(_ store: SyncStateStore, at expected: Int) async throws -> Int {
            for _ in 0 ..< 200 where store.pendingOutboxCount != expected {
                try await Task.sleep(for: .milliseconds(10))
            }
            return store.pendingOutboxCount
        }

        @Test("a mixed queue shows the three rows that still go out")
        func bannerCountsWaitingRows() async throws {
            let fixture = try OutboxWaitingCountTests.Fixture()
            try await fixture.seedMixedQueue()
            let store = makeStore()
            store.bindOutbox(fixture.queue)

            #expect(try await settle(store, at: 3) == 3)
            let later = Date().addingTimeInterval(24 * 3600)
            #expect(store.attention(now: later) == .queued(3))
        }

        @Test("held rows alone never raise the waiting glyph")
        func heldRowsAloneShowNothing() async throws {
            let fixture = try OutboxWaitingCountTests.Fixture()
            try await fixture.row("parked", lastError: "parked:not_stored status=422")
            try await fixture.row("over-budget", attempts: 8, lastError: "Serverfehler")
            let store = makeStore()
            store.bindOutbox(fixture.queue)
            // One waiting row arrives after the binding: the count must land on
            // exactly that one, not on three.
            try await fixture.row("plain")
            #expect(try await settle(store, at: 1) == 1)

            let ops = await fixture.queue.snapshot
            let plain = try #require(ops.first { $0.idempotencyKey == "plain" })
            try await fixture.queue.remove(id: plain.id)
            #expect(try await settle(store, at: 0) == 0)
            // An hour on: past the queued delay, well inside the stale window.
            let attention = store.attention(now: Date().addingTimeInterval(3600))
            #expect(attention == nil, "no icloud.slash for held rows")
        }
    }
#endif
