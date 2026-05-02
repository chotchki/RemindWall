import ComposableArchitecture
import Dao
import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@testable import EditSettingsNew_BusSettings

@MainActor
@Suite("MonitoredStops Feature Tests", .dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
    $0.uuid = .incrementing
})
struct MonitoredStopsFeatureTests {

    @Test("addButtonTapped opens AddMonitoredStop sheet with next sortOrder")
    func addOpensSheet() async {
        let store = TestStore(initialState: MonitoredStopsFeature.State()) {
            MonitoredStopsFeature()
        }
        store.exhaustivity = .off

        await store.send(.addButtonTapped) {
            $0.destination = .addStop(AddMonitoredStopFeature.State(sortOrder: 0))
        }
    }

    @Test("save delegate inserts a row and refreshes the list")
    func saveDelegateInserts() async throws {
        @Dependency(\.defaultDatabase) var database

        var initial = MonitoredStopsFeature.State()
        initial.destination = .addStop(AddMonitoredStopFeature.State(sortOrder: 0))

        let store = TestStore(initialState: initial) {
            MonitoredStopsFeature()
        }
        store.exhaustivity = .off

        let draft = MonitoredStop.Draft(
            label: "School bus",
            stopId: "1_75403",
            routeId: "1_100224",
            routeShortName: "12",
            sortOrder: 0
        )

        await store.send(.destination(.presented(.addStop(.delegate(.saveStop(draft))))))
        await store.finish()

        let stops = try await database.read { db in
            try MonitoredStop.all.fetchAll(db)
        }
        #expect(stops.contains { $0.stopId == "1_75403" && $0.label == "School bus" })
    }

    @Test("delete removes a row from the database")
    func deleteRemoves() async throws {
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.uuid) var uuid

        let id = MonitoredStop.ID(uuid())
        try await database.write { db in
            try MonitoredStop.insert {
                MonitoredStop(
                    id: id,
                    label: "To delete",
                    stopId: "1_111",
                    routeId: "1_a",
                    routeShortName: "A",
                    sortOrder: 0
                )
            }.execute(db)
        }

        let store = TestStore(initialState: MonitoredStopsFeature.State()) {
            MonitoredStopsFeature()
        }
        store.exhaustivity = .off

        await store.send(.deleteStop(id))
        await store.finish()

        let stops = try await database.read { db in
            try MonitoredStop.all.fetchAll(db)
        }
        #expect(stops.contains { $0.id == id } == false)
    }
}
