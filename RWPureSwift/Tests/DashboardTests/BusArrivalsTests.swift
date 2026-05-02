import AppTypes
import ComposableArchitecture
import Dao
import DependenciesTestSupport
import Foundation
import Testing
import TransitAPI

@testable import Dashboard

@MainActor
@Suite("BusArrivals Feature Tests", .dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
    $0.uuid = .incrementing
})
struct BusArrivalsTests {

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// April 6, 2026 is a Monday — covered by the default Mon–Fri window.
    private static let monday0700 = utc.date(from: DateComponents(
        year: 2026, month: 4, day: 6, hour: 7, minute: 0
    ))!

    /// April 5, 2026 is a Sunday — outside the default Mon–Fri window.
    private static let sunday0700 = utc.date(from: DateComponents(
        year: 2026, month: 4, day: 5, hour: 7, minute: 0
    ))!

    @Test("startMonitoring fires immediate tick then loops")
    func startMonitoring() async {
        let clock = TestClock()

        let store = TestStore(initialState: BusArrivalsFeature.State()) {
            BusArrivalsFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(Self.monday0700)
            $0.calendar = Self.utc
        }

        store.exhaustivity = .off

        await store.send(.startMonitoring)
        await store.receive(\.tick)
        await store.receive(\._arrivalsLoaded)

        await store.finish()
    }

    @Test("tick outside window clears arrivals without calling api")
    func outsideWindowClears() async {
        let apiCalled = LockIsolated(false)

        var initial = BusArrivalsFeature.State()
        initial.$enabled.withLock { $0 = true }
        initial.$window.withLock { $0 = .default }

        let store = TestStore(initialState: initial) {
            BusArrivalsFeature()
        } withDependencies: {
            $0.date = .constant(Self.sunday0700)
            $0.calendar = Self.utc
            $0.transitAPI.fetchArrivals = { _, _ in
                apiCalled.setValue(true)
                return []
            }
            $0.transitKeyStore.read = { "key" }
        }

        await store.send(.tick)
        await store.receive(._arrivalsLoaded([], inWindow: false, error: nil))

        #expect(apiCalled.value == false)
    }

    @Test("tick inside window with no monitored stops short-circuits")
    func inWindowNoStops() async {
        var initial = BusArrivalsFeature.State()
        initial.$enabled.withLock { $0 = true }
        initial.$window.withLock { $0 = .default }

        let store = TestStore(initialState: initial) {
            BusArrivalsFeature()
        } withDependencies: {
            $0.date = .constant(Self.monday0700)
            $0.calendar = Self.utc
            $0.transitKeyStore.read = { "key" }
        }

        await store.send(.tick)
        await store.receive(._arrivalsLoaded([], inWindow: true, error: nil)) {
            $0.inWindow = true
        }
    }

    @Test("dedup: two monitored entries sharing stopId trigger one api call")
    func dedupesByStopId() async throws {
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.uuid) var uuid

        try await database.write { db in
            try MonitoredStop.insert {
                MonitoredStop(
                    id: MonitoredStop.ID(uuid()),
                    label: "Bus A",
                    stopId: "1_75403",
                    routeId: "1_a",
                    routeShortName: "A",
                    sortOrder: 0
                )
                MonitoredStop(
                    id: MonitoredStop.ID(uuid()),
                    label: "Bus B",
                    stopId: "1_75403",
                    routeId: "1_b",
                    routeShortName: "B",
                    sortOrder: 1
                )
            }.execute(db)
        }

        let callCount = LockIsolated(0)

        var initial = BusArrivalsFeature.State()
        initial.$enabled.withLock { $0 = true }
        initial.$window.withLock { $0 = .default }
        try await initial.$monitoredStops.load(MonitoredStop.all.order(by: \.sortOrder))

        let store = TestStore(initialState: initial) {
            BusArrivalsFeature()
        } withDependencies: {
            $0.date = .constant(Self.monday0700)
            $0.calendar = Self.utc
            $0.transitKeyStore.read = { "key" }
            $0.transitAPI.fetchArrivals = { _, stopId in
                callCount.withValue { $0 += 1 }
                #expect(stopId == "1_75403")
                return []
            }
        }
        store.exhaustivity = .off

        await store.send(.tick)
        await store.receive(\._arrivalsLoaded)

        #expect(callCount.value == 1, "expected one api call for the shared stopId, got \(callCount.value)")
    }

    @Test("client-side route filter picks correct route")
    func routeFilter() async throws {
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.uuid) var uuid

        let stopId = "1_75403"
        try await database.write { db in
            try MonitoredStop.insert {
                MonitoredStop(
                    id: MonitoredStop.ID(uuid()),
                    label: "School",
                    stopId: stopId,
                    routeId: "1_b",
                    routeShortName: "B",
                    sortOrder: 0
                )
            }.execute(db)
        }

        let predictedB = Date(timeIntervalSince1970: 1_746_119_300)

        var initial = BusArrivalsFeature.State()
        initial.$enabled.withLock { $0 = true }
        initial.$window.withLock { $0 = .default }
        try await initial.$monitoredStops.load(MonitoredStop.all.order(by: \.sortOrder))

        let store = TestStore(initialState: initial) {
            BusArrivalsFeature()
        } withDependencies: {
            $0.date = .constant(Self.monday0700)
            $0.calendar = Self.utc
            $0.transitKeyStore.read = { "key" }
            $0.transitAPI.fetchArrivals = { _, _ in
                [
                    ArrivalPrediction(
                        stopId: stopId, routeId: "1_a", tripId: "t1",
                        tripHeadsign: "Wrong",
                        scheduledArrival: Date(timeIntervalSince1970: 1_746_118_900),
                        predictedArrival: Date(timeIntervalSince1970: 1_746_118_900),
                        isPredicted: true,
                        lastUpdate: nil
                    ),
                    ArrivalPrediction(
                        stopId: stopId, routeId: "1_b", tripId: "t2",
                        tripHeadsign: "Right",
                        scheduledArrival: predictedB,
                        predictedArrival: predictedB,
                        isPredicted: true,
                        lastUpdate: nil
                    )
                ]
            }
        }
        store.exhaustivity = .off

        await store.send(.tick)
        await store.receive(\._arrivalsLoaded) { state in
            #expect(state.arrivals.count == 1)
            #expect(state.arrivals.first?.routeShortName == "B")
        }
    }

    @Test("error path populates lastError")
    func errorPath() async throws {
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.uuid) var uuid

        try await database.write { db in
            try MonitoredStop.insert {
                MonitoredStop(
                    id: MonitoredStop.ID(uuid()),
                    label: "School",
                    stopId: "1_1",
                    routeId: "1_a",
                    routeShortName: "A",
                    sortOrder: 0
                )
            }.execute(db)
        }

        var initial = BusArrivalsFeature.State()
        initial.$enabled.withLock { $0 = true }
        initial.$window.withLock { $0 = .default }
        try await initial.$monitoredStops.load(MonitoredStop.all.order(by: \.sortOrder))

        let store = TestStore(initialState: initial) {
            BusArrivalsFeature()
        } withDependencies: {
            $0.date = .constant(Self.monday0700)
            $0.calendar = Self.utc
            $0.transitKeyStore.read = { "key" }
            $0.transitAPI.fetchArrivals = { _, _ in throw TransitAPIError.unauthorized }
        }
        store.exhaustivity = .off

        await store.send(.tick)
        await store.receive(\._arrivalsLoaded) { state in
            #expect(state.lastError != nil)
            #expect(state.arrivals.isEmpty)
        }
    }

    @Test("makeDisplay flags lateness > 90s as late")
    func makeDisplayLate() {
        let stop = MonitoredStop(
            id: .init(rawValue: UUID()),
            label: "Bus", stopId: "1_1", routeId: "1_a",
            routeShortName: "A", sortOrder: 0
        )
        let now = Date(timeIntervalSince1970: 1_000_000)
        let scheduled = Date(timeIntervalSince1970: 1_000_120)  // +120s
        let predicted = Date(timeIntervalSince1970: 1_000_300)  // +180s after scheduled
        let arrival = ArrivalPrediction(
            stopId: "1_1", routeId: "1_a", tripId: "t",
            tripHeadsign: "X",
            scheduledArrival: scheduled,
            predictedArrival: predicted,
            isPredicted: true,
            lastUpdate: nil
        )
        let display = makeDisplay(stop: stop, soonest: arrival, now: now)
        #expect(display?.isLate == true)
        #expect(display?.isLive == true)
    }

    @Test("makeDisplay flags lateness ≤ 90s as on time")
    func makeDisplayOnTime() {
        let stop = MonitoredStop(
            id: .init(rawValue: UUID()),
            label: "Bus", stopId: "1_1", routeId: "1_a",
            routeShortName: "A", sortOrder: 0
        )
        let now = Date(timeIntervalSince1970: 1_000_000)
        let scheduled = Date(timeIntervalSince1970: 1_000_120)
        let predicted = Date(timeIntervalSince1970: 1_000_180) // +60s late, under threshold
        let arrival = ArrivalPrediction(
            stopId: "1_1", routeId: "1_a", tripId: "t",
            tripHeadsign: "X",
            scheduledArrival: scheduled,
            predictedArrival: predicted,
            isPredicted: true,
            lastUpdate: nil
        )
        let display = makeDisplay(stop: stop, soonest: arrival, now: now)
        #expect(display?.isLate == false)
        #expect(display?.isLive == true)
    }

    @Test("makeDisplay returns nil when no arrival")
    func makeDisplayNil() {
        let stop = MonitoredStop(
            id: .init(rawValue: UUID()),
            label: "Bus", stopId: "1_1", routeId: "1_a",
            routeShortName: "A", sortOrder: 0
        )
        #expect(makeDisplay(stop: stop, soonest: nil, now: Date()) == nil)
    }

    @Test("makeDisplay marks scheduled-only arrival as not live")
    func makeDisplayScheduledOnly() {
        let stop = MonitoredStop(
            id: .init(rawValue: UUID()),
            label: "Bus", stopId: "1_1", routeId: "1_a",
            routeShortName: "A", sortOrder: 0
        )
        let now = Date(timeIntervalSince1970: 1_000_000)
        let arrival = ArrivalPrediction(
            stopId: "1_1", routeId: "1_a", tripId: "t",
            tripHeadsign: "X",
            scheduledArrival: Date(timeIntervalSince1970: 1_000_300),
            predictedArrival: nil,
            isPredicted: false,
            lastUpdate: nil
        )
        let display = makeDisplay(stop: stop, soonest: arrival, now: now)
        #expect(display?.isLive == false)
        #expect(display?.isLate == false)
        #expect(display?.etaText.contains("scheduled") == true)
    }
}
