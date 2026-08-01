import AppTypes
import ComposableArchitecture
import Dao
import DependenciesTestSupport
import Foundation
import Testing
import TrafficAPI

@testable import Dashboard

@MainActor
@Suite("TrafficAlerts Feature Tests", .dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
    $0.uuid = .incrementing
    // .syncedSetting stamps lastModified when tests set window/origin.
    $0.date = .constant(Date(timeIntervalSince1970: 0))
})
struct TrafficAlertsTests {

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// April 6, 2026 is a Monday — inside the default Mon–Fri window.
    private static let monday0700 = utc.date(from: DateComponents(
        year: 2026, month: 4, day: 6, hour: 7, minute: 0
    ))!

    /// April 5, 2026 is a Sunday — outside the default window.
    private static let sunday0700 = utc.date(from: DateComponents(
        year: 2026, month: 4, day: 5, hour: 7, minute: 0
    ))!

    private static let home = HomeOrigin(latitude: 47.52, longitude: -122.39, name: "Home")

    @discardableResult
    private func seedRoute(
        label: String = "School run",
        latitude: Double = 47.5423,
        longitude: Double = -122.3866,
        normalMinutes: Int = 12,
        sortOrder: Int = 0
    ) async -> MonitoredRoute.ID {
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.uuid) var uuid
        let id = MonitoredRoute.ID(uuid())
        try! await database.write { db in
            try MonitoredRoute.insert {
                MonitoredRoute(
                    id: id,
                    label: label,
                    destinationLatitude: latitude,
                    destinationLongitude: longitude,
                    destinationName: label,
                    normalMinutes: normalMinutes,
                    sortOrder: sortOrder
                )
            }.execute(db)
        }
        return id
    }

    @Test("out-of-window tick clears the rail without touching the API")
    func outOfWindow() async {
        await seedRoute()

        let store = TestStore(initialState: TrafficAlertsFeature.State()) {
            TrafficAlertsFeature()
        } withDependencies: {
            $0.date = .constant(Self.sunday0700)
            $0.calendar = Self.utc
            // trafficAPI deliberately unstubbed: a call would fail the test.
        }
        store.state.$homeOrigin.withLock { $0 = Self.home }

        await store.send(.tick)
        // The seeded route's default window excludes Sunday; the exact
        // receive proves no API call happened.
        await store.receive(._routesLoaded([], error: nil))
    }

    @Test("in-window tick builds one display route per monitored route with late math")
    func inWindowFetch() async {
        await seedRoute(label: "School run", normalMinutes: 12, sortOrder: 0)
        await seedRoute(label: "Ferry run", latitude: 47.6026, longitude: -122.3393, normalMinutes: 25, sortOrder: 1)

        let store = TestStore(initialState: TrafficAlertsFeature.State()) {
            TrafficAlertsFeature()
        } withDependencies: {
            $0.date = .constant(Self.monday0700)
            $0.calendar = Self.utc
            $0.trafficAPI.calculateETA = { _, destination in
                // School run gets 18 min (late vs norm 12+5); ferry 20 (fine vs 25).
                destination.latitude == 47.5423
                    ? DriveETA(expectedTravelTime: 18 * 60, distanceMeters: 9000)
                    : DriveETA(expectedTravelTime: 20 * 60, distanceMeters: 12000)
            }
        }
        store.exhaustivity = .off
        store.state.$homeOrigin.withLock { $0 = Self.home }

        await store.send(.tick)
        await store.receive(\._routesLoaded)

        let routes = store.state.displayRoutes
        #expect(routes.map(\.label) == ["School run", "Ferry run"])
        #expect(routes.map(\.etaMinutes) == [18, 20])
        #expect(routes.map(\.isLate) == [true, false])
        #expect(store.state.lastError == nil)
    }

    @Test("routes without a home origin surface the fix, not a blank rail")
    func missingOrigin() async {
        await seedRoute()

        let store = TestStore(initialState: TrafficAlertsFeature.State()) {
            TrafficAlertsFeature()
        } withDependencies: {
            $0.date = .constant(Self.monday0700)
            $0.calendar = Self.utc
        }
        await store.send(.tick)
        await store.receive(._routesLoaded([], error: "home origin not set")) {
            $0.lastError = "home origin not set"
        }
        #expect(store.state.railCards.map(\.priority) == [.errorChip])
    }

    @Test("an API failure collapses to a single error chip")
    func apiFailure() async {
        await seedRoute()

        let store = TestStore(initialState: TrafficAlertsFeature.State()) {
            TrafficAlertsFeature()
        } withDependencies: {
            $0.date = .constant(Self.monday0700)
            $0.calendar = Self.utc
            $0.trafficAPI.calculateETA = { _, _ in throw TrafficAPIError.noRoute }
        }
        store.exhaustivity = .off
        store.state.$homeOrigin.withLock { $0 = Self.home }

        await store.send(.tick)
        await store.receive(\._routesLoaded)

        #expect(store.state.displayRoutes.isEmpty)
        #expect(store.state.lastError != nil)
        #expect(store.state.railCards.count == 1)
        #expect(store.state.railCards.first?.priority == .errorChip)
    }

    @Test("per-watch gating: a disabled route never drives to the API")
    func disabledRouteSkipped() async {
        await seedRoute(label: "Active", normalMinutes: 12, sortOrder: 0)
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.uuid) var uuid
        try! await database.write { db in
            try MonitoredRoute.insert {
                MonitoredRoute(
                    id: MonitoredRoute.ID(uuid()),
                    label: "Switched off",
                    destinationLatitude: 47.61, destinationLongitude: -122.20,
                    destinationName: "Bellevue",
                    normalMinutes: 30, sortOrder: 1,
                    enabled: false
                )
            }.execute(db)
        }

        let fetched = LockIsolated<[Double]>([])
        let store = TestStore(initialState: TrafficAlertsFeature.State()) {
            TrafficAlertsFeature()
        } withDependencies: {
            $0.date = .constant(Self.monday0700)
            $0.calendar = Self.utc
            $0.trafficAPI.calculateETA = { _, destination in
                fetched.withValue { $0.append(destination.latitude) }
                return DriveETA(expectedTravelTime: 10 * 60, distanceMeters: 5000)
            }
        }
        store.exhaustivity = .off
        store.state.$homeOrigin.withLock { $0 = Self.home }

        await store.send(.tick)
        await store.receive(\._routesLoaded)

        #expect(fetched.value == [47.5423])
    }

    @Test("late math: over normal-plus-threshold is late, at the boundary is not")
    func lateBoundary() {
        let route = MonitoredRoute(
            id: MonitoredRoute.ID(UUID()),
            label: "School run",
            destinationLatitude: 0, destinationLongitude: 0,
            destinationName: "School",
            normalMinutes: 12,
            sortOrder: 0
        )
        // Threshold is 5: 17 min is the boundary (not late), 18 is late.
        #expect(!makeDisplayRoute(route: route, eta: DriveETA(expectedTravelTime: 17 * 60, distanceMeters: 0)).isLate)
        #expect(makeDisplayRoute(route: route, eta: DriveETA(expectedTravelTime: 18 * 60, distanceMeters: 0)).isLate)
        // Round-up feeds the comparison: 17:10 driving is 18 min, late.
        #expect(makeDisplayRoute(route: route, eta: DriveETA(expectedTravelTime: 17 * 60 + 10, distanceMeters: 0)).isLate)
    }

    @Test("rail cards map late to slowRoute and on-time to onTimeRoute")
    func railCardPriorities() {
        var state = TrafficAlertsFeature.State()
        state.displayRoutes = [
            DisplayRoute(
                id: MonitoredRoute.ID(UUID()), label: "School run",
                etaMinutes: 18, normalMinutes: 12, etaSeconds: 18 * 60, isLate: true
            ),
            DisplayRoute(
                id: MonitoredRoute.ID(UUID()), label: "Ferry run",
                etaMinutes: 20, normalMinutes: 25, etaSeconds: 20 * 60, isLate: false
            ),
        ]

        #expect(state.railCards.map(\.priority) == [.slowRoute, .onTimeRoute])
        #expect(state.railCards.first?.content == .drive(label: "School run", etaText: "18 min", isLate: true))
        // Error chip only appears when there is nothing to show.
        state.lastError = "timeout"
        #expect(state.railCards.count == 2)
    }
}
