import AppTypes
import ComposableArchitecture
import Dependencies
import DependenciesTestSupport
import Foundation
import ScreenControl
import Testing

@testable import ScreenOffMonitor

private func makeDate(hour: Int, minute: Int) -> Date {
    var cal = Calendar.current
    cal.timeZone = TimeZone.current
    var components = cal.dateComponents([.year, .month, .day], from: Date())
    components.hour = hour
    components.minute = minute
    components.second = 0
    return cal.date(from: components)!
}

/// Applies a 22:00-06:00 off-window THROUGH the store — direct shared
/// mutations on a TestStore are auto-accounted, while pre-store ones surface
/// as phantom "unexpected changes" on the first assertion-free send.
@MainActor
private func applyNightSchedule(
    _ store: TestStore<ScreenOffMonitorFeature.State, ScreenOffMonitorFeature.Action>
) {
    store.state.$schedule.withLock {
        $0 = ScreenOffSchedule(startHour: 22, startMinute: 0, endHour: 6, endMinute: 0)
    }
}

@MainActor
@Suite("ScreenOffMonitor Feature Tests")
struct ScreenOffMonitorTests {

    @Test("startMonitoring sets isMonitoring and fires immediate tick")
    func startMonitoring() async {
        let clock = TestClock()

        let store = TestStore(initialState: ScreenOffMonitorFeature.State()) {
            ScreenOffMonitorFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(makeDate(hour: 15, minute: 0))
            $0.calendar = .current
        }

        await store.send(.startMonitoring) {
            $0.isMonitoring = true
        }
        // No schedule -> tick decides nothing, no work actions.
        await store.receive(\.tick)

        await store.send(.stopMonitoring) {
            $0.isMonitoring = false
        }
        await store.finish()
    }

    @Test("already monitoring ignores duplicate startMonitoring")
    func duplicateStart() async {
        let clock = TestClock()

        let store = TestStore(initialState: {
            var state = ScreenOffMonitorFeature.State()
            state.isMonitoring = true
            return state
        }()) {
            ScreenOffMonitorFeature()
        } withDependencies: {
            $0.continuousClock = clock
        }

        await store.send(.startMonitoring)
    }

    @Test("entering the off window dims write-only: set 0, panel off, confirm")
    func enterOffWindow() async {
        let dimCalls = LockIsolated<[String]>([])

        let store = TestStore(initialState: {
            var state = ScreenOffMonitorFeature.State()
            state.isSlideshowPlaying = true
            return state
        }()) {
            ScreenOffMonitorFeature()
        } withDependencies: {
            $0.date = .constant(makeDate(hour: 23, minute: 0))
            $0.calendar = .current
            $0.screenControl.getBrightness = { 0.75 }
            $0.screenControl.setBrightness = { value in dimCalls.withValue { $0.append("set \(value)") } }
            $0.screenControl.setDisplayPower = { on in dimCalls.withValue { $0.append("power \(on)") } }
        }
        applyNightSchedule(store)

        await store.send(.tick)
        await store.receive(\._dim)
        await store.receive(\._dimConfirmed) {
            $0.isDimmed = true
            $0.savedBrightness = 0.75
        }
        // Brightness zeroed while awake, THEN panel off.
        #expect(dimCalls.value == ["set 0.0", "power false"])
    }

    @Test("unreadable brightness still dims; restore falls back to full bright")
    func dimWithUnreadableBrightness() async {
        let calls = LockIsolated<[String]>([])

        let store = TestStore(initialState: {
            var state = ScreenOffMonitorFeature.State()
            state.isSlideshowPlaying = true
            return state
        }()) {
            ScreenOffMonitorFeature()
        } withDependencies: {
            $0.date = .constant(makeDate(hour: 23, minute: 0))
            $0.calendar = .current
            // The kiosk's LG: reads are garbage and throw downstream.
            $0.screenControl.getBrightness = { throw ScreenControlError.daemonError(status: 502, message: "implausible") }
            $0.screenControl.setBrightness = { value in calls.withValue { $0.append("set \(value)") } }
            $0.screenControl.setDisplayPower = { on in calls.withValue { $0.append("power \(on)") } }
        }
        applyNightSchedule(store)

        await store.send(.tick)
        await store.receive(\._dim)
        await store.receive(\._dimConfirmed) {
            $0.isDimmed = true
            $0.savedBrightness = nil  // garbage read never becomes a restore target
        }

        // Restore must use the 1.0 fallback, wake first.
        await store.send(._restore)
        await store.receive(\._restoreConfirmed) {
            $0.isDimmed = false
            $0.savedBrightness = nil
        }
        #expect(calls.value == ["set 0.0", "power false", "power true", "set 1.0"])
    }

    @Test("leaving the off window restores: wake panel, then saved level")
    func leaveOffWindow() async {
        let calls = LockIsolated<[String]>([])

        let store = TestStore(initialState: {
            var state = ScreenOffMonitorFeature.State()
            state.isSlideshowPlaying = true
            state.isDimmed = true
            state.savedBrightness = 0.6
            return state
        }()) {
            ScreenOffMonitorFeature()
        } withDependencies: {
            $0.date = .constant(makeDate(hour: 8, minute: 0))
            $0.calendar = .current
            $0.screenControl.setBrightness = { value in calls.withValue { $0.append("set \(value)") } }
            $0.screenControl.setDisplayPower = { on in calls.withValue { $0.append("power \(on)") } }
        }
        applyNightSchedule(store)

        await store.send(.tick)
        await store.receive(\._restore)
        await store.receive(\._restoreConfirmed) {
            $0.isDimmed = false
            $0.savedBrightness = nil
        }
        #expect(calls.value == ["power true", "set 0.6"])
    }

    @Test("no schedule means the tick decides nothing")
    func noSchedule() async {
        let store = TestStore(initialState: {
            var state = ScreenOffMonitorFeature.State()
            state.isSlideshowPlaying = true
            return state
        }()) {
            ScreenOffMonitorFeature()
        } withDependencies: {
            $0.date = .constant(makeDate(hour: 23, minute: 0))
            $0.calendar = .current
        }

        await store.send(.tick)
    }

    @Test("no dimming when slideshow not playing")
    func noDimmingWithoutSlideshow() async {
        let store = TestStore(initialState: {
            var state = ScreenOffMonitorFeature.State()
            state.isSlideshowPlaying = false
            return state
        }()) {
            ScreenOffMonitorFeature()
        } withDependencies: {
            $0.date = .constant(makeDate(hour: 23, minute: 0))
            $0.calendar = .current
        }
        applyNightSchedule(store)

        await store.send(.tick)
    }

    @Test("late reminders force the screen back on mid-window")
    func undimsWhenRemindersBecomeLate() async {
        let calls = LockIsolated<[String]>([])

        let store = TestStore(initialState: {
            var state = ScreenOffMonitorFeature.State()
            state.isSlideshowPlaying = true
            state.isDimmed = true
            state.savedBrightness = 0.8
            state.hasLateReminders = true
            return state
        }()) {
            ScreenOffMonitorFeature()
        } withDependencies: {
            $0.date = .constant(makeDate(hour: 23, minute: 0))
            $0.calendar = .current
            $0.screenControl.setBrightness = { value in calls.withValue { $0.append("set \(value)") } }
            $0.screenControl.setDisplayPower = { on in calls.withValue { $0.append("power \(on)") } }
        }
        applyNightSchedule(store)

        await store.send(.tick)
        await store.receive(\._restore)
        await store.receive(\._restoreConfirmed) {
            $0.isDimmed = false
            $0.savedBrightness = nil
        }
        #expect(calls.value == ["power true", "set 0.8"])
    }

    @Test("failed dim is NOT confirmed - the next tick retries it")
    func dimFailureRetriesNextTick() async {
        let attempts = LockIsolated(0)

        let store = TestStore(initialState: {
            var state = ScreenOffMonitorFeature.State()
            state.isSlideshowPlaying = true
            return state
        }()) {
            ScreenOffMonitorFeature()
        } withDependencies: {
            $0.date = .constant(makeDate(hour: 23, minute: 0))
            $0.calendar = .current
            $0.screenControl.getBrightness = { 0.75 }
            $0.screenControl.setBrightness = { _ in
                attempts.withValue { $0 += 1 }
                throw ScreenControlError.daemonUnreachable("down")
            }
            $0.screenControl.setDisplayPower = { _ in }
        }
        applyNightSchedule(store)

        await store.send(.tick)
        await store.receive(\._dim)   // fails, no confirmation, isDimmed stays false
        await store.finish()
        #expect(attempts.value == 1)

        // The state machine self-heals: an identical tick re-issues the dim.
        await store.send(.tick)
        await store.receive(\._dim)
        await store.finish()
        #expect(attempts.value == 2)
        #expect(store.state.isDimmed == false)
    }

    @Test("failed restore keeps isDimmed so the next tick retries - the force-on guarantee")
    func restoreFailureRetriesNextTick() async {
        let powerAttempts = LockIsolated(0)

        let store = TestStore(initialState: {
            var state = ScreenOffMonitorFeature.State()
            state.isSlideshowPlaying = true
            state.isDimmed = true
            state.hasLateReminders = true
            return state
        }()) {
            ScreenOffMonitorFeature()
        } withDependencies: {
            $0.date = .constant(makeDate(hour: 23, minute: 0))
            $0.calendar = .current
            $0.screenControl.setDisplayPower = { _ in
                powerAttempts.withValue { $0 += 1 }
                throw ScreenControlError.daemonUnreachable("down")
            }
        }
        applyNightSchedule(store)

        await store.send(.tick)
        await store.receive(\._restore)
        await store.finish()
        #expect(store.state.isDimmed == true)

        await store.send(.tick)
        await store.receive(\._restore)
        await store.finish()
        #expect(powerAttempts.value == 2)
    }

    @Test("stopMonitoring while dimmed restores best-effort and resets state")
    func stopWhileDimmed() async {
        let calls = LockIsolated<[String]>([])

        let store = TestStore(initialState: {
            var state = ScreenOffMonitorFeature.State()
            state.isMonitoring = true
            state.isDimmed = true
            state.savedBrightness = 0.9
            return state
        }()) {
            ScreenOffMonitorFeature()
        } withDependencies: {
            $0.screenControl.setBrightness = { value in calls.withValue { $0.append("set \(value)") } }
            $0.screenControl.setDisplayPower = { on in calls.withValue { $0.append("power \(on)") } }
        }

        await store.send(.stopMonitoring) {
            $0.isMonitoring = false
            $0.isDimmed = false
            $0.savedBrightness = nil
        }
        await store.finish()
        #expect(calls.value == ["power true", "set 0.9"])
    }
}
