import Foundation
@testable import HealthLog
import SwiftData
import Synchronization
import Testing

// swiftlint:disable force_unwrapping

/// W1 (1.3.0, #126 1.1/1.3, HealthLog#1173) — the replay side.
///
/// * A timeout or a missing connection no longer counts against the retry
///   budget: the row goes out again after its back-off, on every pass, and is
///   never held for the seven days before the dead-letter sweep.
/// * The update path: rows a 1.2.0 install pushed over budget with such
///   failures are re-queued once after the update; parked and unconfirmed rows
///   stay where they are.
/// * A pass that hangs no longer blocks every later pass until the app is
///   restarted: a trigger after the watchdog timeout starts a new pass, and the
///   hung one, once it returns, neither clears the new pass's guard nor walks
///   the queue any further.
///
/// Real `APIClient` over `MockURLProtocol`, allergy fixtures from server
/// v1.39.0 (`src/app/api/allergies/route.ts`), as in
/// `OutboxReplayInterruptionTests`.
@Suite(
    "W1 — transient failures re-send, the 1.2.0 update path, the replay watchdog",
    .serialized,
    .isolatedSkipRegister,
    .mockURLSession
)
struct OutboxTransientReplayTests {
    static let owner = "account-w1-replay"

    static let allergyCreated = Data(#"""
    {"data":{"id":"srv-w1-1","substance":"Penicillin","category":"MEDICATION","type":"ALLERGY",
    "severity":"SEVERE","status":"ACTIVE","onsetAt":null,"reaction":null,"note":null,
    "createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}}
    """#.utf8)

    static func reply(_ req: URLRequest, _ status: Int, _ body: Data?) -> (HTTPURLResponse, Data?) {
        (
            HTTPURLResponse(
                url: req.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!,
            body
        )
    }

    private func makeReplay(
        outbox: OutboxQueue,
        clock: C4Clock = C4Clock(),
        maxAttempts: Int = 8,
        updatePathDefaults: (@Sendable () -> UserDefaults)? = nil,
        runWatchdogTimeout: TimeInterval = OutboxReplayService.defaultRunWatchdogTimeout,
        serverHealthDegraded: (@Sendable () async -> Bool)? = nil
    ) -> OutboxReplayService {
        let env = AppEnvironment(
            baseURL: URL(string: "https://test.healthlog.local")!,
            bundleID: "dev.healthlog.app",
            appVersion: "1.3.0",
            buildNumber: "1"
        )
        let keychain = InMemoryKeychain()
        try? keychain.setString("bearer-w1", forKey: KeychainKey.authToken)
        try? keychain.setString(Self.owner, forKey: KeychainKey.userID)
        let api = APIClient(environment: env, keychain: keychain, sessionConfiguration: .mock())
        return OutboxReplayService(
            outbox: outbox,
            measurementsRepo: MeasurementsRepository(api: api, outbox: outbox),
            moodRepo: MoodRepository(api: api, outbox: outbox),
            medicationsRepo: MedicationsRepository(api: api, outbox: outbox),
            allergiesRepo: AllergiesRepository(api: api, outbox: outbox),
            currentUserProvider: { Self.owner },
            maxAttempts: maxAttempts,
            attemptBackoff: 0,
            clock: { clock.now },
            serverHealthDegraded: serverHealthDegraded,
            runWatchdogTimeout: runWatchdogTimeout,
            updatePathDefaults: updatePathDefaults
        )
    }

    @discardableResult
    private func enqueueAllergy(
        _ outbox: OutboxQueue,
        _ substance: String,
        attempts: Int = 0,
        lastError: String? = nil
    ) async throws -> UUID {
        let op = try OutboxQueue.Operation(
            kind: .createAllergy,
            payload: JSONEncoder.hlDefault.encode(
                OutboxQueue.Payloads.CreateAllergy(body: AllergyCreate(substance: substance, category: .medication))
            ),
            idempotencyKey: "w1-\(substance)",
            attempts: attempts,
            clientEntityId: "optimistic-\(substance)"
        )
        try await outbox.enqueue(op)
        if let lastError { try await outbox.touchAttempt(id: op.id, lastError: lastError) }
        return op.id
    }

    private func row(_ outbox: OutboxQueue, _ substance: String) async -> OutboxQueue.Operation? {
        await outbox.snapshot.first { $0.idempotencyKey == "w1-\(substance)" }
    }

    // MARK: - Transient failures

    @Test("a timeout or no connection is stamped, not counted, and the row keeps going out", arguments: [
        URLError.Code.timedOut, URLError.Code.notConnectedToInternet
    ])
    func connectivityFailureIsNotCounted(_ code: URLError.Code) async throws {
        let outbox = try OutboxQueue(inMemory: true, currentOwnerProvider: { Self.owner })
        try await enqueueAllergy(outbox, "Penicillin")
        let keys = Mutex<Set<String>>([])
        MockURLProtocol.install { req in
            keys.withLock { _ = $0.insert(req.value(forHTTPHeaderField: "Idempotency-Key") ?? "") }
            throw URLError(code)
        }
        // A budget of two: under 1.2.0 the second failure held the row.
        let replay = makeReplay(outbox: outbox, maxAttempts: 2)

        for _ in 0 ..< 3 {
            await replay.runOnce()
        }

        let row = try #require(await row(outbox, "Penicillin"))
        #expect(row.attempts == 0, "the network's fault is not the write's")
        #expect(row.lastAttemptAt != nil, "stamped, so the back-off applies")
        #expect(await outbox.waitingCount(in: outbox.snapshot, maxAttempts: 2) == 1, "still waiting, not held")
        #expect(keys.withLock { $0 } == ["w1-Penicillin"])
        #expect(await outbox.deadLetterCount == 0)
    }

    // MARK: - Update path from 1.2.0

    /// A 1.2.0 install, written to disk: a row a timeout pushed over budget, an
    /// unconfirmed row over budget, and a parked row over budget.
    private func seed122Install(at url: URL) async throws {
        let container = try OutboxStore.makePersistent(storeURL: url)
        let outbox = OutboxQueue(
            testContainer: container,
            currentOwnerProvider: { Self.owner },
            currentAuthTokenProvider: { "bearer-w1" }
        )
        try await enqueueAllergy(outbox, "Timeout", attempts: 8, lastError: "Netzwerk-Fehler: timeout")
        let since = Int(Date().timeIntervalSince1970)
        try await enqueueAllergy(outbox, "Unconfirmed", attempts: 8, lastError: "unconfirmed:since=\(since)")
        try await enqueueAllergy(outbox, "Parked", attempts: 8, lastError: "parked:not_stored status=422")
    }

    @Test("update path: a 1.2.0 row over budget from timeouts is re-queued once and sent")
    func updatePathRequeuesOnce() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("w1-update-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("outbox.sqlite")
        let suite = "w1.update-path.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        try await seed122Install(at: url)

        // The 1.3.0 launch: a new process opens the same file.
        let outbox = try OutboxQueue(
            testContainer: OutboxStore.makePersistent(storeURL: url),
            currentOwnerProvider: { Self.owner },
            currentAuthTokenProvider: { "bearer-w1" }
        )
        #expect(await outbox.waitingCount(in: outbox.snapshot) == 0, "1.2.0 left all three held")
        let keys = Mutex<[String]>([])
        MockURLProtocol.install { req in
            keys.withLock { $0.append(req.value(forHTTPHeaderField: "Idempotency-Key") ?? "") }
            return Self.reply(req, 201, Self.allergyCreated)
        }

        await makeReplay(outbox: outbox, updatePathDefaults: { UserDefaults(suiteName: suite) ?? .standard }).runOnce()

        #expect(keys.withLock { $0 } == ["w1-Timeout"], "only the re-queued row went out")
        #expect(await row(outbox, "Timeout") == nil, "sent and delivered")
        #expect(await row(outbox, "Unconfirmed")?.attempts == 8, "an unconfirmed row keeps its window")
        let parked = try #require(await row(outbox, "Parked"))
        #expect(parked.attempts == 8)
        #expect(parked.lastError == "parked:not_stored status=422", "a real refusal keeps its reason")
        #expect(defaults.bool(forKey: OutboxReplayService.updatePathRequeueKey))

        // Once only: a row that reaches the budget later is not re-queued by
        // the next launch.
        try await enqueueAllergy(outbox, "Later", attempts: 8, lastError: "Serverfehler")
        await makeReplay(outbox: outbox, updatePathDefaults: { UserDefaults(suiteName: suite) ?? .standard }).runOnce()
        #expect(await row(outbox, "Later")?.attempts == 8)
        #expect(keys.withLock { $0 } == ["w1-Timeout"])
    }

    // MARK: - Watchdog

    @Test("a hung pass blocks later triggers only until the watchdog timeout")
    func watchdogReplacesAHungPass() async throws {
        let outbox = try OutboxQueue(inMemory: true, currentOwnerProvider: { Self.owner })
        try await enqueueAllergy(outbox, "Penicillin")
        let keys = Mutex<[String]>([])
        MockURLProtocol.install { req in
            keys.withLock { $0.append(req.value(forHTTPHeaderField: "Idempotency-Key") ?? "") }
            return Self.reply(req, 201, Self.allergyCreated)
        }
        // The first pass hangs in an await that never returns on its own (the
        // field suspect is a HealthKit or probe callback); the test stands in
        // with the server-health probe, the first await of every pass.
        let hang = HangingProbe()
        let clock = C4Clock()
        let replay = makeReplay(
            outbox: outbox,
            clock: clock,
            runWatchdogTimeout: 600,
            serverHealthDegraded: { await hang.probe() }
        )

        let hung = Task { await replay.runOnce() }
        while await !hang.isHanging {
            try await Task.sleep(for: .milliseconds(5))
        }

        // Inside the timeout a trigger is turned away, as before.
        await replay.runOnce()
        #expect(keys.withLock { $0 }.isEmpty)
        #expect(await replay.isRunning)

        // Past it, the trigger runs a pass of its own and drains the row.
        clock.advance(by: 601)
        await replay.runOnce()
        #expect(keys.withLock { $0 } == ["w1-Penicillin"])
        #expect(await outbox.snapshot.isEmpty)
        #expect(await replay.isRunning == false, "the new pass released the guard")

        // The hung pass returns late: it must neither take the guard back nor
        // walk the queue.
        try await enqueueAllergy(outbox, "Latex")
        await hang.release()
        await hung.value
        #expect(await replay.isRunning == false)
        #expect(keys.withLock { $0 } == ["w1-Penicillin"], "the superseded pass sent nothing")

        // And the next trigger runs at once.
        await replay.runOnce()
        #expect(keys.withLock { $0 } == ["w1-Penicillin", "w1-Latex"])
        #expect(await outbox.snapshot.isEmpty)
    }
}

/// The first call hangs until ``release()``; every later call answers at once.
actor HangingProbe {
    private var calls = 0
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var isHanging = false

    func probe() async -> Bool {
        calls += 1
        guard calls == 1 else { return false }
        isHanging = true
        await withCheckedContinuation { waiter = $0 }
        return false
    }

    func release() {
        waiter?.resume()
        waiter = nil
    }
}
