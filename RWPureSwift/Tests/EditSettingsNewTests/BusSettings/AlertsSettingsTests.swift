import AppTypes
import ComposableArchitecture
import Dao
import DependenciesTestSupport
import Foundation
import Testing
import TrafficAPI

@testable import EditSettingsNew_BusSettings

@MainActor
@Suite("AlertsSettings Feature Tests", .dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
    $0.uuid = .incrementing
    $0.date = .constant(Date(timeIntervalSince1970: 0))
})
struct AlertsSettingsTests {

    @discardableResult
    private func seedStop(sortOrder: Int = 0) async -> MonitoredStop.ID {
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.uuid) var uuid
        let id = MonitoredStop.ID(uuid())
        try! await database.write { db in
            try MonitoredStop.insert {
                MonitoredStop(
                    id: id, label: "School bus", stopId: "1_75403", routeId: "1_100224",
                    routeShortName: "12", sortOrder: sortOrder
                )
            }.execute(db)
        }
        return id
    }

    @discardableResult
    private func seedRoute(sortOrder: Int = 0) async -> MonitoredRoute.ID {
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.uuid) var uuid
        let id = MonitoredRoute.ID(uuid())
        try! await database.write { db in
            try MonitoredRoute.insert {
                MonitoredRoute(
                    id: id, label: "School run",
                    destinationLatitude: 47.5423, destinationLongitude: -122.3866,
                    destinationName: "Maple Elementary", normalMinutes: 12, sortOrder: sortOrder
                )
            }.execute(db)
        }
        return id
    }

    @Test("the watch list holds bus stops and driving routes as peers")
    func watchesUnify() async {
        await seedStop()
        await seedRoute()

        let state = AlertsSettingsFeature.State()
        #expect(state.watches.count == 2)
        #expect(state.watches[0].chipText == "12")
        #expect(state.watches[1].chipText == "🚗")
        #expect(state.watches[1].whereText == "to Maple Elementary")
        let allEnabled = state.watches.allSatisfy(\.enabled)
        #expect(allEnabled)
    }

    @Test("toggling a watch writes its enabled column")
    func toggleWrites() async throws {
        let stopId = await seedStop()
        @Dependency(\.defaultDatabase) var database

        let store = TestStore(initialState: AlertsSettingsFeature.State()) {
            AlertsSettingsFeature()
        }
        store.exhaustivity = .off

        await store.send(.watchToggled(.bus(stopId), false))
        await store.finish()

        let stored = try await database.read { db in
            try MonitoredStop.find(stopId).fetchOne(db)
        }
        #expect(stored?.enabled == false)
        #expect(store.state.watches.first?.enabled == false)
    }

    @Test("a saved drive draft inserts a route with per-watch defaults")
    func addDriveInserts() async throws {
        @Dependency(\.defaultDatabase) var database

        let store = TestStore(initialState: AlertsSettingsFeature.State()) {
            AlertsSettingsFeature()
        }
        store.exhaustivity = .off

        await store.send(.addDriveTapped)
        await store.send(.destination(.presented(.addDrive(.delegate(.saveRoute(
            MonitoredRoute.Draft(
                label: "School run",
                destinationLatitude: 47.5423, destinationLongitude: -122.3866,
                destinationName: "Maple Elementary", normalMinutes: 12, sortOrder: 0,
                window: nil, enabled: true
            )
        ))))))
        await store.finish()

        let routes = try await database.read { db in
            try MonitoredRoute.all.fetchAll(db)
        }
        #expect(routes.count == 1)
        #expect(routes.first?.enabled == true)
        #expect(routes.first?.window == nil)
        #expect(store.state.watches.count == 1)
    }

    @Test("a detail remove request deletes the row and closes the sheet")
    func removeDeletes() async throws {
        let stopId = await seedStop()
        @Dependency(\.defaultDatabase) var database

        let store = TestStore(initialState: AlertsSettingsFeature.State()) {
            AlertsSettingsFeature()
        }
        store.exhaustivity = .off

        await store.send(.watchTapped(.bus(stopId)))
        #expect(store.state.destination != nil)

        await store.send(.destination(.presented(.detail(.delegate(.removeRequested(.bus(stopId)))))))
        await store.finish()

        #expect(store.state.destination == nil)
        let remaining = try await database.read { db in
            try MonitoredStop.all.fetchAll(db)
        }
        #expect(remaining.isEmpty)
        #expect(store.state.watches.isEmpty)
    }

    @Test("windowSummary self-describes the row")
    func windowSummary() {
        let watch = Watch.bus(MonitoredStop(
            id: MonitoredStop.ID(UUID()), label: "School bus", stopId: "1_1",
            routeId: "1_a", routeShortName: "12", sortOrder: 0
        ))
        // nil window reads as the default Mon-Fri 6:30-9:00.
        #expect(watch.windowSummary == "MTWTF · 6:30 AM–9:00 AM")
    }
}
