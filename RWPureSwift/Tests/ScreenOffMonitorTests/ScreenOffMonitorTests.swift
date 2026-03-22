import AppTypes
import ComposableArchitecture
import Dependencies
import DependenciesTestSupport
import Foundation
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
            $0.screenControl.getBrightness = { 0.75 }
            $0.screenControl.setBrightness = { _ in }
        }

        await store.send(.startMonitoring) {
            $0.isMonitoring = true
        }

        // The immediate tick fires
        await store.receive(\.tick)

        // No schedule set, so shouldDim = false
        await store.receive(\._evaluated)

        await store.send(.stopMonitoring) {
            $0.isMonitoring = false
        }
    }

    @Test("dims screen when entering off window")
    func enterOffWindow() async {
        let clock = TestClock()
        let brightnessSet = LockIsolated<CGFloat?>(nil)

        let state: ScreenOffMonitorFeature.State = {
            var s = ScreenOffMonitorFeature.State()
            s.$schedule.withLock { $0 = .default } // 22:00-06:00
            return s
        }()

        let store = TestStore(initialState: state) {
            ScreenOffMonitorFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(makeDate(hour: 23, minute: 0))
            $0.calendar = .current
            $0.screenControl.getBrightness = { 0.75 }
            $0.screenControl.setBrightness = { value in brightnessSet.setValue(value) }
        }

        await store.send(.startMonitoring) {
            $0.isMonitoring = true
        }

        await store.receive(\.tick)

        await store.receive(\._evaluated) {
            $0.isDimmed = true
            $0.savedBrightness = 0.75
        }

        #expect(brightnessSet.value == 0.0)

        await store.send(.stopMonitoring) {
            $0.isMonitoring = false
            $0.isDimmed = false
            $0.savedBrightness = nil
        }
    }

    @Test("restores brightness when leaving off window")
    func leaveOffWindow() async {
        let clock = TestClock()
        let brightnessSet = LockIsolated<CGFloat?>(nil)

        // Start in a dimmed state
        let state: ScreenOffMonitorFeature.State = {
            var s = ScreenOffMonitorFeature.State()
            s.$schedule.withLock { $0 = .default } // 22:00-06:00
            s.isDimmed = true
            s.savedBrightness = 0.8
            return s
        }()

        let store = TestStore(initialState: state) {
            ScreenOffMonitorFeature()
        } withDependencies: {
            $0.continuousClock = clock
            // Time is outside the off window
            $0.date = .constant(makeDate(hour: 10, minute: 0))
            $0.calendar = .current
            $0.screenControl.getBrightness = { 0.0 }
            $0.screenControl.setBrightness = { value in brightnessSet.setValue(value) }
        }

        await store.send(.startMonitoring) {
            $0.isMonitoring = true
        }

        await store.receive(\.tick)

        await store.receive(\._evaluated) {
            $0.isDimmed = false
            $0.savedBrightness = nil
        }

        #expect(brightnessSet.value == 0.8)

        await store.send(.stopMonitoring) {
            $0.isMonitoring = false
        }
    }

    @Test("no schedule means no dimming")
    func noSchedule() async {
        let clock = TestClock()
        let brightnessWasSet = LockIsolated(false)

        let store = TestStore(initialState: ScreenOffMonitorFeature.State()) {
            ScreenOffMonitorFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(makeDate(hour: 23, minute: 0))
            $0.calendar = .current
            $0.screenControl.getBrightness = { 0.75 }
            $0.screenControl.setBrightness = { _ in brightnessWasSet.setValue(true) }
        }

        await store.send(.startMonitoring) {
            $0.isMonitoring = true
        }

        await store.receive(\.tick)
        await store.receive(\._evaluated)

        #expect(brightnessWasSet.value == false)

        await store.send(.stopMonitoring) {
            $0.isMonitoring = false
        }
    }

    @Test("stopMonitoring restores brightness if dimmed")
    func stopWhileDimmed() async {
        let clock = TestClock()
        let brightnessSet = LockIsolated<CGFloat?>(nil)

        let state: ScreenOffMonitorFeature.State = {
            var s = ScreenOffMonitorFeature.State()
            s.$schedule.withLock { $0 = .default }
            s.isDimmed = true
            s.savedBrightness = 0.6
            s.isMonitoring = true
            return s
        }()

        let store = TestStore(initialState: state) {
            ScreenOffMonitorFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(makeDate(hour: 23, minute: 0))
            $0.calendar = .current
            $0.screenControl.getBrightness = { 0.0 }
            $0.screenControl.setBrightness = { value in brightnessSet.setValue(value) }
        }

        await store.send(.stopMonitoring) {
            $0.isMonitoring = false
            $0.isDimmed = false
            $0.savedBrightness = nil
        }

        #expect(brightnessSet.value == 0.6)
    }

    @Test("already monitoring ignores duplicate startMonitoring")
    func duplicateStart() async {
        let clock = TestClock()

        var state = ScreenOffMonitorFeature.State()
        state.isMonitoring = true

        let store = TestStore(initialState: state) {
            ScreenOffMonitorFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(makeDate(hour: 15, minute: 0))
            $0.calendar = .current
            $0.screenControl.getBrightness = { 0.75 }
            $0.screenControl.setBrightness = { _ in }
        }

        await store.send(.startMonitoring)
        // No state change, no effects
    }
}
