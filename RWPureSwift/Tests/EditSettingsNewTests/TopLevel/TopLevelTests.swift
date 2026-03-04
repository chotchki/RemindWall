import AppTypes
import ComposableArchitecture
import Dao
import DependenciesTestSupport
import Foundation
import Testing

@testable import EditSettingsNew_Trackees
@testable import EditSettingsNew_TopLevel

@MainActor
@Suite("Settings Feature Tests", .dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
    $0.uuid = .incrementing
})
struct SettingsFeatureTests {

    @Test("startSlideshow action returns no effect")
    func startSlideshow() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }

        await store.send(.startSlideshow)
    }

    @Test("trackees action is forwarded without side effects")
    func trackeesAction() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }

        await store.send(.trackees(.onAppear))
        await store.finish()
    }

    @Test("albumPicker action is forwarded without side effects")
    func albumPickerAction() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.photoKitAlbums.libraryAccess = { .notDetermined }
        }

        await store.send(.albumPicker(.onAppear))
    }

    @Test("calendarPicker action is forwarded without side effects")
    func calendarPickerAction() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.calendarAsync.calendarAccess = { .notDetermined }
        }

        await store.send(.calendarPicker(.onAppear))
    }

    @Test("addButtonTapped via trackees presents add trackee sheet")
    func addTrackeeFromSettings() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }

        store.exhaustivity = .off

        await store.send(.trackees(.addButtonTapped)) {
            $0.trackeesState.$destination.wrappedValue = .addTrackee(
                AddTrackeeFeature.State(
                    trackee: Trackee(id: Trackee.ID(UUID(0)), name: "")
                )
            )
        }
    }

    @Test("slideshowToggled off clears selected album")
    func slideshowToggledOff() async {
        var state = SettingsFeature.State()
        state.albumPickerState.$selectedAlbum.withLock { $0 = AlbumLocalId("test-album") }

        let store = TestStore(initialState: state) {
            SettingsFeature()
        }

        await store.send(.slideshowToggled(false)) {
            $0.albumPickerState.$selectedAlbum.withLock { $0 = nil }
        }
    }

    @Test("slideshowToggled on sets selected album to empty placeholder")
    func slideshowToggledOn() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }

        await store.send(.slideshowToggled(true)) {
            $0.albumPickerState.$selectedAlbum.withLock { $0 = AlbumLocalId("") }
        }
    }

    @Test("calendarToggled on sets selected calendar to empty placeholder")
    func calendarToggledOn() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }

        await store.send(.calendarToggled(true)) {
            $0.calendarPickerState.$selectedCalendar.withLock { $0 = CalendarId("") }
        }
    }

    @Test("calendarToggled off clears selected calendar")
    func calendarToggledOff() async {
        var state = SettingsFeature.State()
        state.calendarPickerState.$selectedCalendar.withLock { $0 = CalendarId("test-calendar") }

        let store = TestStore(initialState: state) {
            SettingsFeature()
        }

        await store.send(.calendarToggled(false)) {
            $0.calendarPickerState.$selectedCalendar.withLock { $0 = nil }
        }
    }

    @Test("screenOffToggled on sets default schedule")
    func screenOffToggledOn() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }

        await store.send(.screenOffToggled(true)) {
            $0.screenOffSettingState.$schedule.withLock { $0 = .default }
        }
    }

    @Test("screenOffToggled off clears schedule")
    func screenOffToggledOff() async {
        var state = SettingsFeature.State()
        state.screenOffSettingState.$schedule.withLock { $0 = .default }

        let store = TestStore(initialState: state) {
            SettingsFeature()
        }

        await store.send(.screenOffToggled(false)) {
            $0.screenOffSettingState.$schedule.withLock { $0 = nil }
        }
    }

    @Test("screenOffSetting action is forwarded without side effects")
    func screenOffSettingAction() async {
        var state = SettingsFeature.State()
        state.screenOffSettingState.$schedule.withLock { $0 = .default }

        let store = TestStore(initialState: state) {
            SettingsFeature()
        }

        await store.send(.screenOffSetting(.setStartTime(hour: 23, minute: 0))) {
            $0.screenOffSettingState.$schedule.withLock {
                $0 = ScreenOffSchedule(startHour: 23, startMinute: 0, endHour: 6, endMinute: 0)
            }
        }
    }

    @Test("initial state has nil screen off schedule")
    func initialScreenOffState() async {
        let state = SettingsFeature.State()
        #expect(state.screenOffSettingState.schedule == nil)
    }

    @Test("initial state has empty path")
    func initialState() async {
        let state = SettingsFeature.State()
        #expect(state.path.count == 0)
    }
}
