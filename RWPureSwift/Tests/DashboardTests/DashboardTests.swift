import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Testing

@testable import Dashboard

@MainActor
@Suite("Dashboard Feature Tests")
struct DashboardTests {

    @Test("onAppear starts all child features")
    func onAppear() async {
        let clock = TestClock()

        let store = TestStore(initialState: DashboardFeature.State()) {
            DashboardFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.defaultDatabase = try! $0.appDatabase()
            $0.date = .constant(Date())
            $0.calendar = .current
        }

        store.exhaustivity = .off

        await store.send(.onAppear)

        // Verify child feature actions are triggered
        await store.receive(\.slideshow.viewAppeared)
        await store.receive(\.alertLoader.startMonitoring)
        await store.receive(\.calendarEvents.startMonitoring)

        await store.finish()
    }

    @Test("slideshow tapReturnToSettings propagates delegate")
    func slideshowReturnToSettings() async {
        let store = TestStore(initialState: DashboardFeature.State()) {
            DashboardFeature()
        }

        store.exhaustivity = .off

        await store.send(.slideshow(.delegate(.tapReturnToSettings)))
        await store.receive(\.delegate.returnToSettings)
    }

    @Test("tappedReturnToSettings sends delegate")
    func tappedReturnToSettings() async {
        let store = TestStore(initialState: DashboardFeature.State()) {
            DashboardFeature()
        }

        store.exhaustivity = .off

        await store.send(.tappedReturnToSettings)
        await store.receive(\.delegate.returnToSettings)
    }
}
