import ComposableArchitecture
import Dao
import DependenciesTestSupport
import Foundation
import Testing

@testable import Dashboard

@MainActor
@Suite("AlertLoader Feature Tests", .dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
})
struct AlertLoaderTests {

    @Test("startMonitoring fires immediate tick then loops")
    func startMonitoring() async {
        let clock = TestClock()

        let store = TestStore(initialState: AlertLoaderFeature.State()) {
            AlertLoaderFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(Date())
            $0.calendar = .current
        }

        store.exhaustivity = .off

        await store.send(.startMonitoring)

        // Immediate tick
        await store.receive(\.tick)
        await store.receive(\._lateTrackeesLoaded)

        await store.finish()
    }

    @Test("tick loads late trackee names from database")
    func tickLoadsFromDatabase() async {
        let store = TestStore(initialState: AlertLoaderFeature.State()) {
            AlertLoaderFeature()
        } withDependencies: {
            $0.date = .constant(Date())
            $0.calendar = .current
        }

        store.exhaustivity = .off

        await store.send(.tick)

        // Seed data has no late reminders by default
        await store.receive(\._lateTrackeesLoaded) {
            $0.lateTrackeeNames = []
        }
    }

    @Test("_lateTrackeesLoaded updates state")
    func lateTrackeesLoadedUpdatesState() async {
        let store = TestStore(initialState: AlertLoaderFeature.State()) {
            AlertLoaderFeature()
        }

        await store.send(._lateTrackeesLoaded(["Alice", "Bob"])) {
            $0.lateTrackeeNames = ["Alice", "Bob"]
        }
    }
}
