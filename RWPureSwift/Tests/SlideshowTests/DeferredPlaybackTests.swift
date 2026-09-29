import ComposableArchitecture
import Testing

@testable import Slideshow

@MainActor
private final class FireLog {
    var fired: [String] = []
}

@MainActor
@Suite("Deferred live photo playback")
struct DeferredPlaybackTests {
    @Test("fires once the delay elapses, not before")
    func firesAfterDelay() async {
        let clock = TestClock()
        let playback = DeferredPlayback(clock: clock)
        let log = FireLog()

        playback.schedule(after: .milliseconds(1500)) { log.fired.append("start") }
        await Task.megaYield()

        await clock.advance(by: .milliseconds(1499))
        #expect(log.fired.isEmpty)

        await clock.advance(by: .milliseconds(1))
        await Task.megaYield()
        #expect(log.fired == ["start"])
    }

    @Test("cancel (dismantle) kills a start that hasn't fired")
    func cancelPreventsStart() async {
        let clock = TestClock()
        let playback = DeferredPlayback(clock: clock)
        let log = FireLog()

        playback.schedule(after: .seconds(1)) { log.fired.append("start") }
        await Task.megaYield()
        playback.cancel()

        await clock.run()
        await Task.megaYield()
        #expect(log.fired.isEmpty)
    }

    @Test("rescheduling replaces the pending start and keeps its own deadline")
    func rescheduleReplaces() async {
        let clock = TestClock()
        let playback = DeferredPlayback(clock: clock)
        let log = FireLog()

        playback.schedule(after: .seconds(1)) { log.fired.append("first") }
        await Task.megaYield()
        await clock.advance(by: .milliseconds(500))
        playback.schedule(after: .seconds(1)) { log.fired.append("second") }
        await Task.megaYield()

        // The first deadline passes with nothing firing...
        await clock.advance(by: .milliseconds(600))
        await Task.megaYield()
        #expect(log.fired.isEmpty)

        // ...and the replacement fires a full delay after it was scheduled.
        await clock.advance(by: .milliseconds(400))
        await Task.megaYield()
        #expect(log.fired == ["second"])
    }

    @Test("the start delay outlasts the crossfade that dismantles the outgoing slide")
    func delayOutlastsCrossfade() {
        #expect(SlideShowFeature.livePhotoStartDelay > .seconds(SlideShowFeature.slideCrossfade))
    }
}
