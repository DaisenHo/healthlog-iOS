import Foundation
@testable import HealthLog
import os
import Testing

// swiftlint:disable force_unwrapping

/// **W3 (iOS 1.3, #126 1.5 / HealthLog#1173)** — the Apple Health dose
/// observer and the one-sweep-at-a-time rule, at the store that owns the toggle.
///
/// HealthKit itself is faked: the simulator delivers no background updates, so
/// what is pinned here is everything around the `HKObserverQuery` (armed once
/// while the toggle is on, stopped when it goes off or the account leaves, a
/// signal becomes a bounded sweep posted under `background`, and concurrent
/// requests never interleave two sweeps over one dose ledger).
@MainActor
@Suite("MedicationHealthSyncStore — dose observer", .serialized, .mockURLSession)
struct MedicationHealthSyncObserverTests {
    // MARK: - Arming

    @Test("the observer is armed once while the toggle is on")
    func observerArmsOnce() async throws {
        let harness = try Harness(enabled: true)
        await harness.store.startObservingIfEnabled()
        await harness.store.startObservingIfEnabled()
        #expect(harness.reader.observeCount == 1)
        await harness.tearDown()
    }

    @Test("nothing is observed while the toggle is off")
    func observerStaysOffWhenDisabled() async throws {
        let harness = try Harness(enabled: false)
        await harness.store.startObservingIfEnabled()
        #expect(harness.reader.observeCount == 0)
        await harness.tearDown()
    }

    @Test("switching the toggle off stops the observer")
    func disablingStopsTheObserver() async throws {
        let harness = try Harness(enabled: true)
        await harness.store.startObservingIfEnabled()
        await harness.store.setEnabled(false)
        #expect(harness.reader.stopCount == 1)
        await harness.tearDown()
    }

    @Test("switching the toggle on arms the observer")
    func enablingArmsTheObserver() async throws {
        let harness = try Harness(enabled: false)
        await harness.store.setEnabled(true)
        #expect(harness.reader.observeCount == 1)
        await harness.tearDown()
    }

    @Test("signing out stops the observer")
    func logoutStopsTheObserver() async throws {
        let harness = try Harness(enabled: true)
        await harness.store.startObservingIfEnabled()
        await harness.store.deactivateOnLogout()
        #expect(harness.reader.stopCount == 1)
        await harness.tearDown()
    }

    // MARK: - A signal

    @Test("a dose signal in the background posts the new dose under background")
    func signalPostsUnderBackground() async throws {
        let harness = try Harness(enabled: true, backgrounded: true)
        await harness.store.startObservingIfEnabled()

        await harness.reader.signal()

        #expect(harness.recorder.bulkPostCount == 1)
        let body = try #require(harness.recorder.lastBulkBody)
        #expect(body["syncTrigger"] as? String == "background")
        let entries = try #require(body["entries"] as? [[String: Any]])
        #expect(entries.first?["externalId"] as? String == "DOSE-0000")
        await harness.tearDown()
    }

    // MARK: - One sweep at a time

    @Test("concurrent requests never run two sweeps at once")
    func concurrentRequestsDoNotInterleave() async throws {
        let harness = try Harness(enabled: true)
        async let first: Void = harness.store.triggerSyncIfEnabled()
        async let second: Void = harness.store.triggerSyncIfEnabled(incrementalOnly: true)
        async let third: Void = harness.store.handleObservedDoseChange()
        _ = await (first, second, third)

        #expect(harness.reader.maxConcurrentSweeps == 1)
        // The first sweep plus exactly one trailing re-run for everything that
        // arrived while it ran.
        #expect(harness.reader.medicationReadCount <= 2)
        await harness.tearDown()
    }
}

// MARK: - Harness

@MainActor
private struct Harness {
    let store: MedicationHealthSyncStore
    let reader: ObservingMedicationReader
    let recorder = MedicationRequestRecorder()
    let suiteName: String

    init(enabled: Bool, backgrounded: Bool = false) throws {
        let (api, keychain) = MedFixtures.makeAPI()
        let owner = "user-w3-\(UUID().uuidString)"
        try keychain.setString(owner, forKey: KeychainKey.userID)
        suiteName = "w3.medobserver.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set(enabled, forKey: MedicationHealthSyncStore.prefKey)
        reader = ObservingMedicationReader()
        store = try MedicationHealthSyncStore(
            repo: MedicationsRepository(api: api, outbox: OutboxQueue(inMemory: true)),
            keychain: keychain,
            reader: reader,
            defaults: defaults,
            isApplicationBackgrounded: { backgrounded }
        )
        store.ledgerStorage = .userDefaults(defaults)
        let sessions = AuthenticatedSessionLeaseRegistry()
        _ = sessions.activate(ownerID: owner)
        store.bindHealthSyncAdmission(.keychainBound(keychain: keychain, registry: sessions))
        AppleHealthMedicationWakeTests.installServer(recorder)
    }

    /// Clears the per-user mirror registry (standard defaults) and the suite.
    func tearDown() async {
        await store.deactivateOnLogout()
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }
}

/// A reader that can be observed: it keeps the handler HealthKit would call,
/// counts arming and stopping, and measures how many sweeps overlap.
private final class ObservingMedicationReader: AppleHealthMedicationReading, @unchecked Sendable {
    private struct State {
        var handler: (@Sendable () async -> Void)?
        var observeCount = 0
        var stopCount = 0
        var medicationReads = 0
        var activeSweeps = 0
        var maxConcurrentSweeps = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var observeCount: Int {
        state.withLock { $0.observeCount }
    }

    var stopCount: Int {
        state.withLock { $0.stopCount }
    }

    var medicationReadCount: Int {
        state.withLock { $0.medicationReads }
    }

    var maxConcurrentSweeps: Int {
        state.withLock { $0.maxConcurrentSweeps }
    }

    var isAvailable: Bool {
        true
    }

    func requestAuthorization() async throws {}

    /// The first read of a sweep. It holds the sweep open for a moment so an
    /// overlapping one would be seen.
    func readMedications() async throws -> [AppleHealthMedicationRecord] {
        state.withLock {
            $0.medicationReads += 1
            $0.activeSweeps += 1
            $0.maxConcurrentSweeps = max($0.maxConcurrentSweeps, $0.activeSweeps)
        }
        try? await Task.sleep(for: .milliseconds(50))
        return [AppleHealthMedicationWakeTests.medication]
    }

    /// The last read of a sweep.
    func readDoseEvents(since _: Date?) async throws -> [AppleHealthDoseRecord] {
        state.withLock { $0.activeSweeps -= 1 }
        return AppleHealthMedicationWakeTests.doses(count: 1)
    }

    func observeDoseEvents(
        _ onChange: @escaping @Sendable () async -> Void
    ) async -> (any AppleHealthDoseEventObservation)? {
        state.withLock {
            $0.handler = onChange
            $0.observeCount += 1
        }
        return FakeObservation(reader: self)
    }

    /// What HealthKit does when a dose is logged.
    func signal() async {
        let handler = state.withLock { $0.handler }
        await handler?()
    }

    fileprivate func noteStop() {
        state.withLock {
            $0.stopCount += 1
            $0.handler = nil
        }
    }

    private struct FakeObservation: AppleHealthDoseEventObservation {
        let reader: ObservingMedicationReader

        func stop() async {
            reader.noteStop()
        }
    }
}

// swiftlint:enable force_unwrapping
