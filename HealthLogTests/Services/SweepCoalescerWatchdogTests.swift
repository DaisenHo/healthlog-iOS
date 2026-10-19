import Foundation
@testable import HealthLog
import Synchronization
import Testing

/// W1 (1.3.0, #126 1.3, HealthLog#1173) — "nur ein Neustart hilft".
///
/// `SweepCoalescer` kept a key in flight until the running body returned. A
/// body that never returned folded every later trigger into a run that would
/// never finish, for the rest of the process. The watchdog lets a trigger that
/// finds a body older than `staleAfter` start a run of its own, and fences the
/// stale run so it neither clears the new run's slot nor starts a re-run.
@Suite("W1 — SweepCoalescer watchdog")
struct SweepCoalescerWatchdogTests {
    /// Settable clock.
    final class Clock: Sendable {
        private let value = Mutex(Date(timeIntervalSince1970: 1_790_000_000))
        var now: Date {
            value.withLock { $0 }
        }

        func advance(by seconds: TimeInterval) {
            value.withLock { $0 = $0.addingTimeInterval(seconds) }
        }
    }

    /// Holds the first body open until released; counts every body run.
    actor Body {
        private(set) var runs = 0
        private var waiter: CheckedContinuation<Void, Never>?

        func run() async {
            runs += 1
            guard runs == 1 else { return }
            await withCheckedContinuation { waiter = $0 }
        }

        func release() {
            waiter?.resume()
            waiter = nil
        }
    }

    @Test("a body that never returns is replaced after staleAfter, not before")
    func staleRunIsReplaced() async {
        let clock = Clock()
        let gate = SweepCoalescer(label: "test", staleAfter: 600, now: { clock.now })
        let body = Body()

        let hung = Task { await gate.run { await body.run() } }
        while await body.runs < 1 {
            await Task.yield()
        }

        // Inside the window: folded, as before.
        await gate.run { await body.run() }
        #expect(await body.runs == 1)

        // Past it: the trigger runs the body itself.
        clock.advance(by: 601)
        await gate.run { await body.run() }
        #expect(await body.runs == 2)

        // The stale run returns late. Its pending re-run flag belonged to the
        // new run, which already ran: no extra body.
        await body.release()
        await hung.value
        #expect(await body.runs == 2)

        // The key is free again.
        await gate.run { await body.run() }
        #expect(await body.runs == 3)
    }
}
