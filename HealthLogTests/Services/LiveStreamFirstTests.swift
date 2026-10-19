#if canImport(HealthKit)
    import Foundation
    import HealthKit
    @testable import HealthLog
    import Synchronization
    import Testing

    /// 1.3 (#127, HealthLog#1204) — new readings do not wait behind history.
    ///
    /// The store below behaves like HealthKit where it matters: rows carry an
    /// insertion position (the anchor) and a start date, an anchored read
    /// returns rows after the anchor in insertion order, and the old history
    /// was inserted long before last night. This suite uses only the API that
    /// 1.2.0 already had, so it runs unchanged against both builds: on 1.2.0
    /// every case is red, because the one shared cursor reads the oldest rows
    /// first and a short wake does not start a walk at all.
    @Suite("Live stream first (#127)")
    struct LiveStreamFirstTests {
        /// Insertion-ordered rows behind the pre-1.3 query seam.
        final class InsertionOrderedStore: AnchoredHealthSampleQuerying, Sendable {
            struct Row: Sendable {
                let anchor: Int
                let start: Date
            }

            let rows: [Row]

            init(rows: [Row]) {
                self.rows = rows
            }

            func page(
                typeIdentifier _: String,
                resumingFrom anchor: HKQueryAnchor?,
                notBefore cutoff: Date,
                limit: Int
            ) async throws -> AnchoredHealthSamplePage {
                let after = anchor.flatMap(position) ?? 0
                // HealthKit's first read is narrowed by its predicate; a resumed
                // read in the shipped source carries none.
                let matching = rows.filter { $0.anchor > after && (anchor != nil || $0.start >= cutoff) }
                let page = Array(matching.prefix(limit))
                let full = page.count >= limit
                let newAnchor = full ? (page.last?.anchor ?? after) : (rows.last?.anchor ?? after)
                return AnchoredHealthSamplePage(
                    samples: page.map(Self.sample),
                    deletedObjectCount: 0,
                    newAnchor: HKQueryAnchor(fromValue: newAnchor),
                    mayHaveMore: full
                )
            }

            private func position(_ anchor: HKQueryAnchor) -> Int? {
                ([0] + rows.map(\.anchor)).first { HKQueryAnchor(fromValue: $0) == anchor }
            }

            static func sample(_ row: Row) -> HKSample {
                HKQuantitySample(
                    type: HKQuantityType(.stepCount),
                    quantity: HKQuantity(unit: .count(), doubleValue: Double(row.anchor)),
                    start: row.start,
                    end: row.start.addingTimeInterval(60)
                )
            }
        }

        /// Accepts every page and remembers the start date of every sample.
        final class RecordingConsumer: HealthSamplePageConsuming, Sendable {
            private let starts = Mutex<[Date]>([])

            var consumedStarts: [Date] {
                starts.withLock { $0 }
            }

            func consume(
                _ samples: [HKSample],
                ofType _: String,
                requiring _: HealthSyncAuthenticatedLease
            ) async -> HealthSyncPageOutcome {
                starts.withLock { $0.append(contentsOf: samples.map(\.startDate)) }
                return ScriptedConsumer.accepted
            }
        }

        /// Years of history inserted first, last night inserted last.
        static func deviceWithHistory(oldRows: Int) -> (InsertionOrderedStore, lastNight: Date) {
            let oldest = Date(timeIntervalSince1970: 1_500_000_000)
            var rows = (1 ... oldRows).map { index in
                InsertionOrderedStore.Row(anchor: index, start: oldest.addingTimeInterval(Double(index) * 600))
            }
            let lastNight = Date().addingTimeInterval(-6 * 3600)
            rows += (1 ... 10).map { index in
                InsertionOrderedStore.Row(anchor: oldRows + index, start: lastNight.addingTimeInterval(Double(index) * 60))
            }
            return (InsertionOrderedStore(rows: rows), lastNight)
        }

        @Test("an observer wake on a partition with years of history delivers last night")
        func observerWakeDeliversLastNight() async throws {
            let registry = AuthenticatedSessionLeaseRegistry()
            let lease = try CollectorFixture.makeLease(registry: registry)
            let (cursors, _) = try await CollectorFixture.makeReplayingStore(backing: CollectorCursorBacking(), lease: lease)
            let (store, lastNight) = Self.deviceWithHistory(oldRows: 3000)
            let consumer = RecordingConsumer()
            let collector = AnchoredHealthSampleCollector(cursors: cursors, query: store, consumer: consumer)

            _ = await collector.collect(
                typeIdentifiers: [CollectorFixture.stepType],
                trigger: .observer,
                notBefore: .distantPast,
                requiring: lease
            )

            #expect(consumer.consumedStarts.contains { $0 >= lastNight })
        }

        @Test("the first foreground pass delivers last night before any old history")
        func foregroundDeliversLastNightFirst() async throws {
            let registry = AuthenticatedSessionLeaseRegistry()
            let lease = try CollectorFixture.makeLease(registry: registry)
            let (cursors, _) = try await CollectorFixture.makeReplayingStore(backing: CollectorCursorBacking(), lease: lease)
            let (store, lastNight) = Self.deviceWithHistory(oldRows: 3000)
            let consumer = RecordingConsumer()
            let collector = AnchoredHealthSampleCollector(cursors: cursors, query: store, consumer: consumer)

            _ = await collector.collect(
                typeIdentifiers: [CollectorFixture.stepType],
                trigger: .foreground,
                notBefore: .distantPast,
                requiring: lease
            )

            let first = try #require(consumer.consumedStarts.first)
            #expect(first >= lastNight)
        }

        @Test("update path: a 1.2.0 partition halfway through its history delivers last night on the next wake")
        func halfwalkedUpgradeDeliversLastNight() async throws {
            let registry = AuthenticatedSessionLeaseRegistry()
            let lease = try CollectorFixture.makeLease(registry: registry)
            let backing = CollectorCursorBacking()
            let (cursors, key) = try await CollectorFixture.makeReplayingStore(backing: backing, lease: lease)
            // The 1.2.0 state: the one shared cursor stands after row 500 of
            // 3000, as #1204's sleep did, and the partition still replays.
            try await cursors.save(HKQueryAnchor(fromValue: 500), for: key, requiring: lease)
            let (store, lastNight) = Self.deviceWithHistory(oldRows: 3000)
            let consumer = RecordingConsumer()
            let collector = AnchoredHealthSampleCollector(cursors: cursors, query: store, consumer: consumer)

            _ = await collector.collect(
                typeIdentifiers: [CollectorFixture.stepType],
                trigger: .appRefresh,
                notBefore: .distantPast,
                requiring: lease
            )

            #expect(consumer.consumedStarts.contains { $0 >= lastNight })
            #expect(!consumer.consumedStarts.contains { $0 < lastNight })
        }
    }
#endif
