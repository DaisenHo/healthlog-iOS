#if canImport(HealthKit)
    import Foundation
    import HealthKit

    // 1.3 (#127, #128) — the history and legacy legs of the collector.
    //
    // Both run only in the budget the live streams left, only for a type
    // whose live stream has reached the present, and only one run at a time.
    // Every page goes through the same consumption and the same commit rule as
    // a live page: a page the server did not terminally accept (and that has
    // no durable retry row) leaves the date cursor exactly where it was.

    extension AnchoredHealthSampleCollector {
        /// One history run over `order`. Types the time budget did not reach
        /// are named `expired`, so the caller can start the next run there.
        func collectHistory(
            order: [String],
            cutoff: Date,
            lease: HealthSyncAuthenticatedLease,
            allowance: HealthSampleHistoryBudget
        ) async -> [String: HistoryResult] {
            let startedAt = clock.uptime()
            if let running = historyRun, startedAt - running.startedAt < HealthSampleSplitPolicy.staleHistoryRun {
                // Another pass walks the same date cursors right now.
                return Dictionary(uniqueKeysWithValues: order.map { ($0, Self.historyResult(0, 0, .deferred, nil, false)) })
            }
            let token = UUID()
            historyRun = (token, startedAt)
            defer {
                if historyRun?.token == token { historyRun = nil }
            }

            let deadline = startedAt + allowance.timeBudget
            var out: [String: HistoryResult] = [:]
            for typeIdentifier in order {
                if Task.isCancelled || clock.uptime() >= deadline {
                    out[typeIdentifier] = Self.historyResult(0, 0, .expired, nil, false)
                    continue
                }
                out[typeIdentifier] = await collectHistoryOne(
                    typeIdentifier,
                    cutoff: cutoff,
                    lease: lease,
                    maxPages: allowance.pagesPerType,
                    deadline: deadline
                )
            }
            return out
        }

        /// Pages, rows and the retry flag one type has used so far in a run.
        struct HistoryTally {
            var pages = 0
            var samplesRead = 0
            var retryPersisted = false

            func result(
                _ disposition: HealthSyncDisposition,
                _ reason: HealthSyncHoldReason?,
                finished: Bool = false
            ) -> HistoryResult {
                AnchoredHealthSampleCollector.historyResult(pages, samplesRead, disposition, reason, finished)
            }

            /// A held page: `retryPersisted` when its rows wait durably,
            /// `expired` when the run was cancelled under it (BG expiry, the
            /// person stopping "Sync everything now").
            func held(_ reason: HealthSyncHoldReason) -> HistoryResult {
                if reason == .cancelled { return result(.expired, reason) }
                return result(retryPersisted ? .retryPersisted : .failed, reason)
            }
        }

        private func collectHistoryOne(
            _ typeIdentifier: String,
            cutoff: Date,
            lease: HealthSyncAuthenticatedLease,
            maxPages: Int,
            deadline: TimeInterval
        ) async -> HistoryResult {
            guard let history, let key = lease.cursorKey(typeIdentifier: typeIdentifier) else {
                return Self.historyResult(0, 0, .failed, .leaseLost, false)
            }
            guard await cursors.permitsCollection(for: key),
                  var state = await cursors.splitState(for: key),
                  state.historyMayRun else
            {
                return Self.historyResult(0, 0, .deferred, nil, false)
            }

            var tally = HistoryTally()
            let limits = (maxPages: maxPages, deadline: deadline)
            if let stopped = await walkBackwards(history, key, &state, &tally, cutoff: cutoff, lease: lease, limits: limits) {
                return stopped
            }
            if let stopped = await walkLegacy(key, &state, &tally, cutoff: cutoff, lease: lease, limits: limits) {
                return stopped
            }
            let finished = state.isHistoryComplete(cutoff: cutoff) && state.legacyWindow(cutoff: cutoff) == nil
            return tally.result(tally.retryPersisted ? .retryPersisted : .succeeded, nil, finished: finished)
        }

        /// Backwards from `liveStart`, newest first, down to the floor. Returns
        /// a result only when the run has to stop for this type.
        private func walkBackwards(
            _ history: any HealthSampleHistoryQuerying,
            _ key: HealthSyncCursorKey,
            _ state: inout HealthSampleSplitState,
            _ tally: inout HistoryTally,
            cutoff: Date,
            lease: HealthSyncAuthenticatedLease,
            limits: (maxPages: Int, deadline: TimeInterval)
        ) async -> HistoryResult? {
            while tally.pages < limits.maxPages, !state.isHistoryComplete(cutoff: cutoff) {
                if let stop = interruption(lease: lease, deadline: limits.deadline) {
                    return tally.result(stop.disposition, stop.reason)
                }
                let floor = state.historyFloor(cutoff: cutoff)
                let window = HealthSampleDateWindow(
                    start: floor == .distantPast ? nil : floor,
                    end: state.historyEnd,
                    endInclusive: state.historyEndInclusive
                )
                let step: HistoryStep
                do {
                    step = try await readHistoryStep(history, key.typeIdentifier, window: window, floor: floor)
                } catch is CancellationError {
                    return tally.result(.expired, .cancelled)
                } catch {
                    logHold(key, reason: .nonterminalEntry)
                    return tally.result(.failed, .nonterminalEntry)
                }

                tally.samplesRead += step.samples.count
                let outcome = await consumer.consume(step.samples, ofType: key.typeIdentifier, requiring: lease)
                tally.retryPersisted = tally.retryPersisted || outcome.durableRetryPersisted
                let decision = await cursors.commitHistory(
                    page: outcome,
                    reachedBack: step.nextEnd,
                    inclusive: step.nextInclusive,
                    for: key,
                    requiring: lease
                )
                tally.pages += 1
                if case let .hold(reason) = decision {
                    logHold(key, reason: reason)
                    return tally.held(reason)
                }
                guard let reread = await cursors.splitState(for: key) else {
                    return tally.result(.failed, .retryPersistenceFailed)
                }
                state = reread
            }
            return nil
        }

        /// The legacy leg of an upgrade: the dates below the replay floor,
        /// read forward from the 1.2.0 cursor, until it comes back short.
        private func walkLegacy(
            _ key: HealthSyncCursorKey,
            _ state: inout HealthSampleSplitState,
            _ tally: inout HistoryTally,
            cutoff: Date,
            lease: HealthSyncAuthenticatedLease,
            limits: (maxPages: Int, deadline: TimeInterval)
        ) async -> HistoryResult? {
            while state.isHistoryComplete(cutoff: cutoff), state.legacyLegActive {
                guard let window = state.legacyWindow(cutoff: cutoff) else {
                    // The walk itself reaches the window now ("Sync everything
                    // now", or no shortcut): nothing is owed below it.
                    await cursors.updateSplit(for: key, requiring: lease) { $0.legacyLegActive = false }
                    state.legacyLegActive = false
                    return nil
                }
                guard tally.pages < limits.maxPages else { return nil }
                if let stop = interruption(lease: lease, deadline: limits.deadline) {
                    return tally.result(stop.disposition, stop.reason)
                }
                let anchor = await HealthKitAnchorArchive.decodeAnchor(
                    cursors.legacyAnchor(for: key),
                    label: key.source.rawValue
                )
                let page: AnchoredHealthSamplePage
                do {
                    page = try await query.page(
                        typeIdentifier: key.typeIdentifier,
                        resumingFrom: anchor,
                        within: window,
                        limit: pageLimit
                    )
                } catch is CancellationError {
                    return tally.result(.expired, .cancelled)
                } catch {
                    logHold(key, reason: .nonterminalEntry)
                    return tally.result(.failed, .nonterminalEntry)
                }
                tally.samplesRead += page.samples.count
                let outcome = await consumer.consume(page.samples, ofType: key.typeIdentifier, requiring: lease)
                tally.retryPersisted = tally.retryPersisted || outcome.durableRetryPersisted
                guard let newAnchor = page.newAnchor,
                      let blob = HealthKitAnchorArchive.encodeAnchor(newAnchor, label: key.source.rawValue) else
                {
                    logHold(key, reason: .retryPersistenceFailed)
                    return tally.result(.failed, .retryPersistenceFailed)
                }
                let decision = await cursors.commitLegacy(page: outcome, anchor: blob, for: key, requiring: lease)
                tally.pages += 1
                if case let .hold(reason) = decision {
                    logHold(key, reason: reason)
                    return tally.held(reason)
                }
                if !page.mayHaveMore {
                    let retired = await cursors.updateSplit(for: key, requiring: lease) { $0.legacyLegActive = false }
                    if retired { state.legacyLegActive = false }
                    return nil
                }
            }
            return nil
        }

        /// One step of the backwards walk and where the cursor goes after it.
        struct HistoryStep {
            let samples: [HKSample]
            let nextEnd: Date
            let nextInclusive: Bool
        }

        /// Reads one page and decides the next cursor. A short page ends the
        /// walk at the floor. A full page moves the end to its oldest start,
        /// inclusive, because more samples may share that instant; when a full
        /// page is entirely that one instant, the whole instant is read at once
        /// so the walk can step past it without losing any of it.
        private func readHistoryStep(
            _ history: any HealthSampleHistoryQuerying,
            _ typeIdentifier: String,
            window: HealthSampleDateWindow,
            floor: Date
        ) async throws -> HistoryStep {
            let samples = try await history.historyPage(typeIdentifier: typeIdentifier, within: window, limit: pageLimit)
            guard samples.count >= pageLimit, let oldest = samples.map(\.startDate).min() else {
                return HistoryStep(samples: samples, nextEnd: floor, nextInclusive: false)
            }
            if let end = window.end, oldest >= end {
                let instant = HealthSampleDateWindow(start: end, end: end, endInclusive: true)
                let whole = try await history.historyPage(typeIdentifier: typeIdentifier, within: instant, limit: nil)
                return HistoryStep(samples: whole, nextEnd: end, nextInclusive: false)
            }
            return HistoryStep(samples: samples, nextEnd: oldest, nextInclusive: true)
        }

        private func interruption(
            lease: HealthSyncAuthenticatedLease,
            deadline: TimeInterval
        ) -> (disposition: HealthSyncDisposition, reason: HealthSyncHoldReason?)? {
            if Task.isCancelled { return (.expired, .cancelled) }
            if let refusal = lease.refusal { return (.failed, refusal.holdReason) }
            if clock.uptime() >= deadline { return (.expired, nil) }
            return nil
        }

        static func historyResult(
            _ pages: Int,
            _ samplesRead: Int,
            _ disposition: HealthSyncDisposition,
            _ holdReason: HealthSyncHoldReason?,
            _ isFinished: Bool
        ) -> HistoryResult {
            HistoryResult(
                pagesCollected: pages,
                samplesRead: samplesRead,
                disposition: disposition,
                holdReason: holdReason,
                isFinished: isFinished
            )
        }
    }
#endif
