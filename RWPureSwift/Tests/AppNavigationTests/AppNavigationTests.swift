import AppTypes
import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Testing

@testable import AppNavigation
@testable import EditSettingsNew_TopLevel

@MainActor
@Suite("AppNavigation Feature Tests", .dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
    $0.uuid = .incrementing
})
struct AppNavigationFeatureTests {

    @Test("initial state is settings screen")
    func initialState() async {
        let state = AppNavigationFeature.State()
        #expect(state.screen == .settings)
    }

    @Test("onAppear starts screen off monitoring")
    func onAppearStartsMonitoring() async {
        let clock = TestClock()

        let store = TestStore(initialState: AppNavigationFeature.State()) {
            AppNavigationFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(Date())
            $0.calendar = .current
            $0.screenControl.getBrightness = { 0.75 }
            $0.screenControl.setBrightness = { _ in }
        }

        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.screenOffMonitor.startMonitoring)
        await store.finish()
    }

    @Test("onAppear with configured slideshow switches to dashboard")
    func onAppearWithConfiguredSlideshow() async {
        let clock = TestClock()

        var state = AppNavigationFeature.State()
        state.settingsState.albumPickerState.$selectedAlbum.withLock { $0 = AlbumLocalId("test-album") }

        let store = TestStore(initialState: state) {
            AppNavigationFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(Date())
            $0.calendar = .current
            $0.screenControl.getBrightness = { 0.75 }
            $0.screenControl.setBrightness = { _ in }
        }

        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.screen = .dashboard
            $0.screenOffMonitorState.isSlideshowPlaying = true
        }
        await store.receive(\.screenOffMonitor.startMonitoring)
        await store.finish()
    }

    @Test("onAppear without configured slideshow stays on settings")
    func onAppearWithoutConfiguredSlideshow() async {
        let clock = TestClock()

        let store = TestStore(initialState: AppNavigationFeature.State()) {
            AppNavigationFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(Date())
            $0.calendar = .current
            $0.screenControl.getBrightness = { 0.75 }
            $0.screenControl.setBrightness = { _ in }
        }

        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.screenOffMonitor.startMonitoring)
        await store.finish()
    }

    @Test("startSlideshow delegate switches to dashboard")
    func startSlideshowSwitchesToDashboard() async {
        let store = TestStore(initialState: AppNavigationFeature.State()) {
            AppNavigationFeature()
        }

        store.exhaustivity = .off

        await store.send(.settings(.startSlideshow))
        await store.receive(\.settings.delegate.startSlideshow) {
            $0.screen = .dashboard
            $0.screenOffMonitorState.isSlideshowPlaying = true
        }
    }

    @Test("showDashboard switches screen to dashboard")
    func showDashboard() async {
        let store = TestStore(initialState: AppNavigationFeature.State()) {
            AppNavigationFeature()
        }

        await store.send(.showDashboard) {
            $0.screen = .dashboard
            $0.screenOffMonitorState.isSlideshowPlaying = true
        }
    }

    @Test("showSettings switches screen to settings")
    func showSettings() async {
        var state = AppNavigationFeature.State()
        state.screen = .dashboard
        state.screenOffMonitorState.isSlideshowPlaying = true

        let store = TestStore(initialState: state) {
            AppNavigationFeature()
        }

        await store.send(.showSettings) {
            $0.screen = .settings
            $0.screenOffMonitorState.isSlideshowPlaying = false
        }
    }

    @Test("dashboard returnToSettings delegate switches to settings")
    func dashboardReturnToSettings() async {
        var state = AppNavigationFeature.State()
        state.screen = .dashboard
        state.screenOffMonitorState.isSlideshowPlaying = true

        let store = TestStore(initialState: state) {
            AppNavigationFeature()
        }

        store.exhaustivity = .off

        await store.send(.dashboard(.delegate(.returnToSettings))) {
            $0.screen = .settings
            $0.screenOffMonitorState.isSlideshowPlaying = false
        }
    }

    @Test("settings action is forwarded without side effects")
    func settingsActionForwarded() async {
        let store = TestStore(initialState: AppNavigationFeature.State()) {
            AppNavigationFeature()
        } withDependencies: {
            $0.photoKitAlbums.libraryAccess = { .notDetermined }
        }

        await store.send(.settings(.albumPicker(.onAppear)))
    }

    @Test("startSlideshow sets isSlideshowPlaying on screen off monitor")
    func startSlideshowSetsSlideshowPlaying() async {
        let store = TestStore(initialState: AppNavigationFeature.State()) {
            AppNavigationFeature()
        }

        store.exhaustivity = .off

        await store.send(.settings(.startSlideshow))
        await store.receive(\.settings.delegate.startSlideshow) {
            $0.screen = .dashboard
            $0.screenOffMonitorState.isSlideshowPlaying = true
        }
    }

    @Test("returnToSettings clears isSlideshowPlaying on screen off monitor")
    func returnToSettingsClearsSlideshowPlaying() async {
        var state = AppNavigationFeature.State()
        state.screen = .dashboard
        state.screenOffMonitorState.isSlideshowPlaying = true

        let store = TestStore(initialState: state) {
            AppNavigationFeature()
        }

        store.exhaustivity = .off

        await store.send(.dashboard(.delegate(.returnToSettings))) {
            $0.screen = .settings
            $0.screenOffMonitorState.isSlideshowPlaying = false
        }
    }

    @Test("lateTrackeesLoaded updates hasLateReminders on screen off monitor")
    func lateTrackeesUpdatesHasLateReminders() async {
        var state = AppNavigationFeature.State()
        state.screen = .dashboard

        let store = TestStore(initialState: state) {
            AppNavigationFeature()
        }

        await store.send(.dashboard(.alertLoader(._lateTrackeesLoaded(["Alice"])))) {
            $0.dashboardState.alertLoaderState.lateTrackeeNames = ["Alice"]
            $0.screenOffMonitorState.hasLateReminders = true
        }

        await store.send(.dashboard(.alertLoader(._lateTrackeesLoaded([])))) {
            $0.dashboardState.alertLoaderState.lateTrackeeNames = []
            $0.screenOffMonitorState.hasLateReminders = false
        }
    }

    @Test("screenOffMonitor action is forwarded without side effects")
    func screenOffMonitorActionForwarded() async {
        let clock = TestClock()

        let store = TestStore(initialState: AppNavigationFeature.State()) {
            AppNavigationFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(Date())
            $0.calendar = .current
            $0.screenControl.getBrightness = { 0.75 }
            $0.screenControl.setBrightness = { _ in }
        }

        store.exhaustivity = .off

        await store.send(.screenOffMonitor(.startMonitoring)) {
            $0.screenOffMonitorState.isMonitoring = true
        }

        await store.finish()
    }
}
