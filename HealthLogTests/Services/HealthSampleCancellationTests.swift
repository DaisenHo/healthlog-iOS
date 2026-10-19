#if canImport(HealthKit) && canImport(SpeziHealthKit)
    import Foundation
    import HealthKit
    @testable import HealthLog
    import Synchronization
    import Testing

    /// W1 (1.3.0, #126 1.1, HealthLog#1173) — "500 geparkt".
    ///
    /// A background window that ends while a page is on the wire cancels the
    /// batch POST. `APIClient` reports that as `HLError.canceled` (a cancelled
    /// task) or `.network(.writeCancelled)` (the task still ran). Up to 1.2.0
    /// neither reached the cancellation arm of `HealthSampleConsumption`: the
    /// whole page (one page is 500 samples) went into the outbox as a retry row
    /// and Sync Diagnostics counted it as parked. A cancellation now holds the
    /// cursor, writes nothing and counts nothing; the next run reads the page
    /// again.
    @Suite("W1 — a cancelled page is left for the next run, never parked")
    struct HealthSampleCancellationTests {
        /// Batch API that fails every POST with one error.
        final class FailingBatchAPI: APIClientProtocol, @unchecked Sendable {
            private let error: Error
            private let calls = Mutex(0)

            init(_ error: Error) {
                self.error = error
            }

            var callCount: Int {
                calls.withLock { $0 }
            }

            func send<T: Decodable & Sendable>(_: APIRequest<T>) async throws -> T {
                calls.withLock { $0 += 1 }
                throw error
            }

            func sendVoid(_: APIRequest<EmptyPayload>) async throws {}

            func download(_: APIRequest<Data>) async throws -> (Data, HTTPURLResponse) {
                throw HLError.unknown("download not implemented")
            }
        }

        /// Records every durable retry the page writes.
        actor RecordingRetry: HealthSyncBatchRetryEnqueuing {
            private(set) var rows: [[HealthKitBatchEntryDTO]] = []

            func enqueueHealthKitRetry(
                _ entries: [HealthKitBatchEntryDTO],
                idempotencyKey _: String,
                requiringCurrentOwner _: String
            ) async throws {
                rows.append(entries)
            }
        }

        struct Transmitted {
            let outcome: HealthSyncPageOutcome
            let tally: HealthSampleServerTally
            let retry: RecordingRetry
            let api: FailingBatchAPI
        }

        private func transmit(failingWith error: Error) async throws -> Transmitted {
            let registry = AuthenticatedSessionLeaseRegistry()
            let lease = try CollectorFixture.makeLease(registry: registry)
            let api = FailingBatchAPI(error)
            let retry = RecordingRetry()
            let gate = HealthSampleWireGate(dailyStatsEnabled: false, hrBucketGate: nil)
            let consumption = HealthSampleConsumption(
                uploader: MeasurementBatchUploader(api: api, throttle: BatchSyncThrottle()),
                gate: gate,
                retry: retry,
                skipRegister: HealthKitSkippedRowRegister(storage: SkipRegisterBacking().storage),
                build: "293"
            )
            let samples = [0.95, 0.96, 0.97].map(SkipFixture.spo2Sample)
            let (outcome, tally) = await consumption.transmitReporting(gate.map(samples), admitted: lease)
            return Transmitted(outcome: outcome, tally: tally, retry: retry, api: api)
        }

        @Test("a background cancellation holds the cursor and parks nothing", arguments: [
            HLError.canceled, HLError.network(.writeCancelled)
        ])
        func cancellationIsNotParked(_ error: HLError) async throws {
            let sent = try await transmit(failingWith: error)
            let (outcome, tally, retry, api) = (sent.outcome, sent.tally, sent.retry, sent.api)

            #expect(api.callCount == 1, "the page did go on the wire")
            #expect(await retry.rows.isEmpty, "no outbox row: nothing waits, nothing is counted")
            #expect(tally == HealthSampleServerTally(), "not parked")
            #expect(outcome.wasCancelled)
            #expect(HealthSyncCursorPolicy.required.decide(outcome) == .hold(reason: .cancelled))
        }

        @Test("a timeout still writes the durable retry, so the cursor may move")
        func timeoutStillParks() async throws {
            let sent = try await transmit(failingWith: HLError.network(.timeout))
            let (outcome, tally, retry) = (sent.outcome, sent.tally, sent.retry)

            #expect(await retry.rows.map(\.count) == [3])
            #expect(tally.parked == 3)
            #expect(HealthSyncCursorPolicy.required.decide(outcome) == .commit)
        }
    }
#endif
