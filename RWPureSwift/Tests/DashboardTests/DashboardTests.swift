import AppTypes
import ComposableArchitecture
import Dao
import Dependencies
import DependenciesTestSupport
import Foundation
import TagScanner
import Testing

@testable import Dashboard

@MainActor
@Suite("Dashboard Feature Tests", .dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
})
struct DashboardTests {

    @Test("onAppear starts all child features and hides cursor")
    func onAppear() async {
        let clock = TestClock()
        let hideCalled = LockIsolated(false)

        let store = TestStore(initialState: DashboardFeature.State()) {
            DashboardFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.defaultDatabase = try! $0.appDatabase()
            $0.date = .constant(Date())
            $0.calendar = .current
            $0.cursorClient.hide = { hideCalled.setValue(true) }
            $0.tagReaderClient.nextTagId = {
                try? await Task.sleep(for: .seconds(100))
                return .noTag
            }
        }

        store.exhaustivity = .off

        await store.send(.onAppear)

        #expect(hideCalled.value == true)

        // Verify child feature actions are triggered
        await store.receive(\.slideshow.viewAppeared)
        await store.receive(\.alertLoader.startMonitoring)
        await store.receive(\.calendarEvents.startMonitoring)
        await store.receive(\.tagScanLoader.startMonitoring)

        await store.finish()
    }

    @Test("onDisappear unhides cursor")
    func onDisappear() async {
        let unhideCalled = LockIsolated(false)

        let store = TestStore(initialState: DashboardFeature.State()) {
            DashboardFeature()
        } withDependencies: {
            $0.cursorClient.unhide = { unhideCalled.setValue(true) }
        }

        await store.send(.onDisappear)

        #expect(unhideCalled.value == true)
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
