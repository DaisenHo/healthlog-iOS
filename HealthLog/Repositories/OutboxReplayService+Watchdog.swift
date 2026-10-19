import Foundation

// W1 (1.3.0, #126 1.3, HealthLog#1173) — "nur ein Neustart hilft".
//
// `runOnce` guarded itself with a bare `isRunning` flag that only the pass's
// own `defer` cleared. A pass whose await never returned therefore kept the
// flag for the rest of the process, and every later trigger (foreground,
// reachability edge, BG drain) returned at once without a word. Nothing in the
// field logs could tell that apart from "nothing to send".
//
// Two parts, in this order:
//
//   * Persisted runtime logging (`notice`, category `outbox`): every pass logs
//     its start, its end with the duration, and every trigger it turned away
//     with the age and the step the running pass is in (`runPhase`). A hung pass
//     now leaves a trail that names where it hangs.
//   * A watchdog: a trigger that finds a pass running longer than
//     `runWatchdogTimeout` starts a new pass instead of returning. The stale
//     pass is fenced by its generation and stops at its next row, so the two
//     never walk the queue together for more than the one row the stale pass
//     may still be waiting on. That row's re-send is harmless: it goes out
//     under its persisted idempotency key.

extension OutboxReplayService {
    /// Ten minutes: far above a real pass (one request per row, each with its
    /// own URLSession timeout), far below "until the next app restart".
    public static let defaultRunWatchdogTimeout: TimeInterval = 10 * 60

    /// Persisted once the 1.2.0 update path ran (see
    /// ``requeueOverBudgetRowsOnce()``).
    static let updatePathRequeueKey = "outbox.requeueRetriableOverBudget.v1_3"

    /// Takes the pass guard, or `nil` when a healthy pass already holds it.
    func beginRun() -> UInt64? {
        let now = clock()
        if isRunning, let started = runStartedAt {
            let age = Int(now.timeIntervalSince(started))
            guard now.timeIntervalSince(started) >= runWatchdogTimeout else {
                // swiftlint:disable:next hllog_public_privacy_interpolation
                HLLog.outbox.notice(
                    "Outbox replay trigger skipped: pass \(runGeneration, privacy: .public) running \(age, privacy: .public)s in \(runPhase, privacy: .public)"
                )
                return nil
            }
            // swiftlint:disable:next hllog_public_privacy_interpolation
            HLLog.outbox.error(
                "Outbox replay pass \(runGeneration, privacy: .public) stuck \(age, privacy: .public)s in \(runPhase, privacy: .public): watchdog starts a new pass"
            )
        }
        runGeneration &+= 1
        isRunning = true
        runStartedAt = now
        runPhase = "start"
        // swiftlint:disable:next hllog_public_privacy_interpolation
        HLLog.outbox.notice("Outbox replay pass \(runGeneration, privacy: .public) begins")
        return runGeneration
    }

    /// Releases the guard, but only for the pass that still owns it: a stale
    /// pass returning late must not clear the flag of the pass that replaced it.
    func endRun(_ generation: UInt64, startedAt: Date) {
        let seconds = Int(clock().timeIntervalSince(startedAt))
        guard isCurrentRun(generation) else {
            // swiftlint:disable:next hllog_public_privacy_interpolation
            HLLog.outbox.notice(
                "Outbox replay pass \(generation, privacy: .public) returned after \(seconds, privacy: .public)s, superseded by \(runGeneration, privacy: .public)"
            )
            return
        }
        isRunning = false
        runStartedAt = nil
        runPhase = "idle"
        // swiftlint:disable:next hllog_public_privacy_interpolation
        HLLog.outbox.notice("Outbox replay pass \(generation, privacy: .public) ended after \(seconds, privacy: .public)s")
    }

    /// The retry budget a row gets before the replay holds it back. Shared with
    /// the waiting count (`OutboxQueue+Backlog`), which must agree with it.
    public static let defaultMaxAttempts = 8

    /// `false` once the watchdog handed the queue to a newer pass; the stale
    /// pass then sends nothing more (its end is logged by ``endRun``).
    func isCurrentRun(_ generation: UInt64) -> Bool {
        generation == runGeneration
    }

    /// The pass's last step, skipped by a superseded pass.
    func finishPass(_ generation: UInt64, now: Date) async {
        guard isCurrentRun(generation) else { return }
        runPhase = "dead-letter sweep"
        await sweepDeadLetters(now: now)
    }

    /// The 1.2.0 update path, once per install: rows a timeout or a lost
    /// connection pushed over the retry budget get it back (see
    /// ``OutboxQueue/requeueRetriableRowsOverBudget(maxAttempts:)``). The flag
    /// is written only after the store write went through, so a failed write
    /// is tried again on the next pass.
    func requeueOverBudgetRowsOnce() async {
        guard let defaults = updatePathDefaults?(), !defaults.bool(forKey: Self.updatePathRequeueKey) else { return }
        runPhase = "update-path requeue"
        do {
            let count = try await outbox.requeueRetriableRowsOverBudget(maxAttempts: maxAttempts)
            defaults.set(true, forKey: Self.updatePathRequeueKey)
            // A count only.
            // swiftlint:disable:next hllog_public_privacy_interpolation
            HLLog.outbox.notice("Outbox update path: \(count, privacy: .public) row(s) over budget re-queued")
        } catch {
            HLLog.outbox.error("Outbox update path re-queue failed, tried again next pass")
        }
    }
}
