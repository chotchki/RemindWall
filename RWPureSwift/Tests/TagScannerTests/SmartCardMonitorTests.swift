import AppTypes
import Testing

@testable import TagScanner

/// Exercises the waiter/buffer logic directly via the test seam — the real Combine
/// pipeline needs CryptoTokenKit hardware, but every lost-scan bug we've had lived
/// in deliver()/nextValidCard(), which these cover.
@Suite(.timeLimit(.minutes(1)))
struct SmartCardMonitorTests {

    @Test("waiter receives a delivered event")
    func waiterReceives() async {
        let monitor = SmartCardMonitor(testing: ())
        let task = Task { await monitor.nextValidCard() }
        while await monitor.pendingWaiterCount == 0 { await Task.yield() }

        await monitor.deliver(.tagPresent(TagSerial([0x04])))
        #expect(await task.value == .tagPresent(TagSerial([0x04])))
    }

    @Test("event with no waiter is buffered for the next caller")
    func buffering() async {
        let monitor = SmartCardMonitor(testing: ())
        await monitor.deliver(.tagPresent(TagSerial([0x01])))
        #expect(await monitor.nextValidCard() == .tagPresent(TagSerial([0x01])))
    }

    @Test("buffered tagPresent survives a trailing decode failure (RF bounce)")
    func bufferPreservesTagPresent() async {
        let monitor = SmartCardMonitor(testing: ())
        await monitor.deliver(.tagPresent(TagSerial([0x01])))
        await monitor.deliver(.tagUnreadable("trailing bounce failure"))
        #expect(await monitor.nextValidCard() == .tagPresent(TagSerial([0x01])))
    }

    @Test("buffered failure is upgraded by a later tagPresent")
    func bufferUpgradedBySuccess() async {
        let monitor = SmartCardMonitor(testing: ())
        await monitor.deliver(.tagUnreadable("first"))
        await monitor.deliver(.tagPresent(TagSerial([0x02])))
        #expect(await monitor.nextValidCard() == .tagPresent(TagSerial([0x02])))
    }

    @Test("newer failure replaces an older buffered failure")
    func failureBufferLastWins() async {
        let monitor = SmartCardMonitor(testing: ())
        await monitor.deliver(.tagUnreadable("first"))
        await monitor.deliver(.tagUnreadable("second"))
        #expect(await monitor.nextValidCard() == .tagUnreadable("second"))
    }

    @Test("cancelled waiter deregisters; the next event reaches a live caller, not a zombie")
    func cancellationDeregisters() async {
        let monitor = SmartCardMonitor(testing: ())

        let task = Task { await monitor.nextValidCard() }
        while await monitor.pendingWaiterCount == 0 { await Task.yield() }

        task.cancel()
        #expect(await task.value == .noTag)

        // Deregistration hops back to the actor via an unstructured Task.
        while await monitor.pendingWaiterCount != 0 { await Task.yield() }

        // The zombie bug: a lone dead waiter used to swallow this event entirely.
        // With deregistration it buffers instead and the next caller gets it.
        await monitor.deliver(.tagPresent(TagSerial([0x03])))
        #expect(await monitor.nextValidCard() == .tagPresent(TagSerial([0x03])))
    }

    @Test("cancellation before the call starts resumes immediately with noTag")
    func preCancelled() async {
        let monitor = SmartCardMonitor(testing: ())
        let task = Task { await monitor.nextValidCard() }
        task.cancel()
        #expect(await task.value == .noTag)
        #expect(await monitor.pendingWaiterCount == 0)
    }

    @Test("stale buffered event is dropped, not replayed as a live scan")
    func staleBufferDropped() async throws {
        let monitor = SmartCardMonitor(testing: (), bufferTTL: .milliseconds(1))
        await monitor.deliver(.tagPresent(TagSerial([0x0A])))
        try await Task.sleep(for: .milliseconds(50))

        // A fresh caller must WAIT (registering as a waiter), not consume the
        // minutes-old tap — that falsely marked meds taken on dashboard return.
        let task = Task { await monitor.nextValidCard() }
        while await monitor.pendingWaiterCount == 0 { await Task.yield() }

        await monitor.deliver(.tagPresent(TagSerial([0x0B])))
        #expect(await task.value == .tagPresent(TagSerial([0x0B])))
    }

    @Test("fresh buffered event within TTL is still consumed")
    func freshBufferConsumed() async {
        let monitor = SmartCardMonitor(testing: (), bufferTTL: .seconds(60))
        await monitor.deliver(.tagPresent(TagSerial([0x0C])))
        #expect(await monitor.nextValidCard() == .tagPresent(TagSerial([0x0C])))
    }

    @Test("cancelled caller does not consume the buffer — the event survives for a live caller")
    func cancelledCallerLeavesBuffer() async {
        let monitor = SmartCardMonitor(testing: ())
        await monitor.deliver(.tagPresent(TagSerial([0x0D])))

        let task = Task {
            // Guarantee cancellation is delivered before the monitor call runs.
            while !Task.isCancelled { await Task.yield() }
            return await monitor.nextValidCard()
        }
        task.cancel()
        #expect(await task.value == .noTag)

        // The buffered tap must still be there for the next live caller.
        #expect(await monitor.nextValidCard() == .tagPresent(TagSerial([0x0D])))
    }

    @Test("deliver broadcasts to every concurrent waiter")
    func broadcast() async {
        let monitor = SmartCardMonitor(testing: ())
        let t1 = Task { await monitor.nextValidCard() }
        let t2 = Task { await monitor.nextValidCard() }
        while await monitor.pendingWaiterCount < 2 { await Task.yield() }

        await monitor.deliver(.tagPresent(TagSerial([0x05])))
        #expect(await t1.value == .tagPresent(TagSerial([0x05])))
        #expect(await t2.value == .tagPresent(TagSerial([0x05])))
    }
}
