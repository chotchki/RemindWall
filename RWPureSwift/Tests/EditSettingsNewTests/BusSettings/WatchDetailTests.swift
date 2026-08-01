import AppTypes
import ComposableArchitecture
import Dao
import DependenciesTestSupport
import Foundation
import Testing

@testable import EditSettingsNew_BusSettings

@MainActor
@Suite("WatchDetail Feature Tests", .dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
    $0.uuid = .incrementing
    $0.date = .constant(Date(timeIntervalSince1970: 0))
})
struct WatchDetailTests {

    private func seededRoute() async -> MonitoredRoute {
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.uuid) var uuid
        let route = MonitoredRoute(
            id: MonitoredRoute.ID(uuid()), label: "School run",
            destinationLatitude: 47.5423, destinationLongitude: -122.3866,
            destinationName: "Maple Elementary", normalMinutes: 12, sortOrder: 0
        )
        try! await database.write { db in
            try MonitoredRoute.insert { route }.execute(db)
        }
        return route
    }

    @Test("window edits persist to the watch's own row")
    func windowEditPersists() async throws {
        let route = await seededRoute()
        @Dependency(\.defaultDatabase) var database

        let store = TestStore(initialState: WatchDetailFeature.State(watch: .drive(route))) {
            WatchDetailFeature()
        }
        store.exhaustivity = .off

        await store.send(.setWindowStart(hour: 7, minute: 45))
        await store.receive(\.delegate.watchChanged)
        await store.send(.toggleWeekday(.Saturday))
        await store.receive(\.delegate.watchChanged)
        await store.finish()

        let stored = try await database.read { db in
            try MonitoredRoute.find(route.id).fetchOne(db)
        }
        let window = try #require(stored?.window)
        #expect(window.startHour == 7)
        #expect(window.startMinute == 45)
        #expect(window.weekdays.contains(.Saturday))
        #expect(store.state.watch.window == window)
    }

    @Test("enable toggle and normal minutes persist")
    func enabledAndMinutesPersist() async throws {
        let route = await seededRoute()
        @Dependency(\.defaultDatabase) var database

        let store = TestStore(initialState: WatchDetailFeature.State(watch: .drive(route))) {
            WatchDetailFeature()
        }
        store.exhaustivity = .off

        await store.send(.enabledToggled(false))
        await store.receive(\.delegate.watchChanged)
        await store.send(.normalMinutesChanged(25))
        await store.receive(\.delegate.watchChanged)
        await store.finish()

        let stored = try await database.read { db in
            try MonitoredRoute.find(route.id).fetchOne(db)
        }
        #expect(stored?.enabled == false)
        #expect(stored?.normalMinutes == 25)
    }

    @Test("remove asks the parent instead of deleting itself")
    func removeDelegates() async {
        let route = await seededRoute()

        let store = TestStore(initialState: WatchDetailFeature.State(watch: .drive(route))) {
            WatchDetailFeature()
        }

        await store.send(.removeTapped)
        await store.receive(.delegate(.removeRequested(.drive(route.id))))
    }
}
