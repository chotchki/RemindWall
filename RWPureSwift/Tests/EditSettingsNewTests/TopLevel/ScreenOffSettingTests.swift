import AppTypes
import ComposableArchitecture
import DependenciesTestSupport
import Testing

@testable import EditSettingsNew_TopLevel

@MainActor
@Suite("ScreenOffSetting Feature Tests")
struct ScreenOffSettingTests {

    @Test("initial state has nil schedule")
    func initialState() async {
        let state = ScreenOffSettingFeature.State()
        #expect(state.schedule == nil)
    }

    // MARK: - Set Actions

    @Test("setStartTime updates start time directly")
    func setStartTime() async {
        var state = ScreenOffSettingFeature.State()
        state.$schedule.withLock { $0 = ScreenOffSchedule(startHour: 22, startMinute: 0, endHour: 6, endMinute: 0) }

        let store = TestStore(initialState: state) {
            ScreenOffSettingFeature()
        }

        await store.send(.setStartTime(hour: 21, minute: 30)) {
            $0.$schedule.withLock { $0 = ScreenOffSchedule(startHour: 21, startMinute: 30, endHour: 6, endMinute: 0) }
        }
    }

    @Test("setEndTime updates end time directly")
    func setEndTime() async {
        var state = ScreenOffSettingFeature.State()
        state.$schedule.withLock { $0 = ScreenOffSchedule(startHour: 22, startMinute: 0, endHour: 6, endMinute: 0) }

        let store = TestStore(initialState: state) {
            ScreenOffSettingFeature()
        }

        await store.send(.setEndTime(hour: 7, minute: 15)) {
            $0.$schedule.withLock { $0 = ScreenOffSchedule(startHour: 22, startMinute: 0, endHour: 7, endMinute: 15) }
        }
    }

    @Test("setSchedule updates both times directly")
    func setSchedule() async {
        var state = ScreenOffSettingFeature.State()
        state.$schedule.withLock { $0 = ScreenOffSchedule(startHour: 22, startMinute: 0, endHour: 6, endMinute: 0) }

        let store = TestStore(initialState: state) {
            ScreenOffSettingFeature()
        }

        await store.send(.setSchedule(startHour: 23, startMinute: 30, endHour: 7, endMinute: 45)) {
            $0.$schedule.withLock { $0 = ScreenOffSchedule(startHour: 23, startMinute: 30, endHour: 7, endMinute: 45) }
        }
    }

    @Test("setStartTime with nil schedule produces no state changes")
    func setStartTimeNilSchedule() async {
        let store = TestStore(initialState: ScreenOffSettingFeature.State()) {
            ScreenOffSettingFeature()
        }
        await store.send(.setStartTime(hour: 10, minute: 30))
    }

    @Test("setStartTime clamps negative values")
    func setStartTimeClamps() async {
        var state = ScreenOffSettingFeature.State()
        state.$schedule.withLock { $0 = ScreenOffSchedule(startHour: 22, startMinute: 0, endHour: 6, endMinute: 0) }

        let store = TestStore(initialState: state) {
            ScreenOffSettingFeature()
        }

        await store.send(.setStartTime(hour: -1, minute: -5)) {
            $0.$schedule.withLock { $0 = ScreenOffSchedule(startHour: 23, startMinute: 55, endHour: 6, endMinute: 0) }
        }
    }

    // MARK: - Nil schedule guard

    @Test("actions with nil schedule produce no state changes")
    func nilScheduleNoOp() async {
        let store = TestStore(initialState: ScreenOffSettingFeature.State()) {
            ScreenOffSettingFeature()
        }

        await store.send(.setStartTime(hour: 10, minute: 30))
        await store.send(.setEndTime(hour: 7, minute: 0))
        await store.send(.setSchedule(startHour: 22, startMinute: 0, endHour: 6, endMinute: 0))
    }

    // MARK: - Test Screen Off

    @Test("testScreenOff dims and restores brightness")
    func testScreenOff() async {
        var state = ScreenOffSettingFeature.State()
        state.$schedule.withLock { $0 = .default }

        let brightnessValues = LockIsolated<[CGFloat]>([])
        let clock = TestClock()

        let store = TestStore(initialState: state) {
            ScreenOffSettingFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.screenControl.getBrightness = { 0.75 }
            $0.screenControl.setBrightness = { value in
                brightnessValues.withValue { $0.append(value) }
            }
        }

        await store.send(.testScreenOff) {
            $0.isTesting = true
        }

        await clock.advance(by: .seconds(1))

        await store.receive(\._testComplete) {
            $0.isTesting = false
        }

        #expect(brightnessValues.value == [0.0, 0.75])
    }

    @Test("testScreenOff ignored while already testing")
    func testScreenOffWhileTesting() async {
        var state = ScreenOffSettingFeature.State()
        state.$schedule.withLock { $0 = .default }
        state.isTesting = true

        let store = TestStore(initialState: state) {
            ScreenOffSettingFeature()
        }

        await store.send(.testScreenOff)
    }
}
