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

    @Test("initial state has empty path")
    func initialState() async {
        let state = SettingsFeature.State()
        #expect(state.path.count == 0)
    }
}
