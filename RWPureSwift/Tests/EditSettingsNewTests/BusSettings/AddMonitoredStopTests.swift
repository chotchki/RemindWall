import ComposableArchitecture
import Dao
import DependenciesTestSupport
import Foundation
import Testing
import TransitAPI

@testable import EditSettingsNew_BusSettings

@MainActor
@Suite("AddMonitoredStop Feature Tests")
struct AddMonitoredStopFeatureTests {

    @Test("agencyChanged resets stop and route lookup state")
    func agencyChangedResets() async {
        var initial = AddMonitoredStopFeature.State(sortOrder: 0)
        initial.lookedUpStop = StopInfo(
            stopId: "1_1", code: "1", name: "Old", routeIds: ["1_a"]
        )
        initial.routeOptions = [
            RouteInfo(routeId: "1_a", shortName: "A", longName: "ALine", agencyId: "1")
        ]
        initial.selectedRouteId = "1_a"

        let store = TestStore(initialState: initial) {
            AddMonitoredStopFeature()
        }

        await store.send(.agencyChanged("3")) {
            $0.agencyId = "3"
            $0.lookedUpStop = nil
            $0.routeOptions = []
            $0.selectedRouteId = nil
        }
    }

    @Test("lookup happy path fetches stop then routes and seeds label")
    func lookupHappyPath() async {
        let stop = StopInfo(
            stopId: "1_75403",
            code: "75403",
            name: "3rd Ave & Pike St",
            routeIds: ["1_100224"]
        )
        let route = RouteInfo(
            routeId: "1_100224",
            shortName: "12",
            longName: "Capitol Hill",
            agencyId: "1"
        )

        var initial = AddMonitoredStopFeature.State(sortOrder: 0)
        initial.stopCode = "75403"

        let store = TestStore(initialState: initial) {
            AddMonitoredStopFeature()
        } withDependencies: {
            $0.transitKeyStore.read = { "key" }
            $0.transitAPI.fetchStop = { _, _ in stop }
            $0.transitAPI.fetchRoute = { _, _ in route }
        }

        await store.send(.lookupTapped) {
            $0.isLooking = true
        }
        await store.receive(\._stopFetched) {
            $0.lookedUpStop = stop
            $0.label = stop.name
        }
        await store.receive(\._routesFetched) {
            $0.routeOptions = [route]
            $0.selectedRouteId = "1_100224"
            $0.isLooking = false
        }
    }

    @Test("lookup with 404 surfaces specific message")
    func lookupNotFound() async {
        var initial = AddMonitoredStopFeature.State(sortOrder: 0)
        initial.stopCode = "99999"

        let store = TestStore(initialState: initial) {
            AddMonitoredStopFeature()
        } withDependencies: {
            $0.transitKeyStore.read = { "key" }
            $0.transitAPI.fetchStop = { _, _ in throw TransitAPIError.notFound }
        }

        await store.send(.lookupTapped) {
            $0.isLooking = true
        }
        await store.receive(\._lookupFailed) {
            $0.isLooking = false
            $0.errorMessage = "Stop not found. Check the agency and stop code."
        }
    }

    @Test("lookup with no stored API key short-circuits with message")
    func lookupNoKey() async {
        var initial = AddMonitoredStopFeature.State(sortOrder: 0)
        initial.stopCode = "75403"

        let store = TestStore(initialState: initial) {
            AddMonitoredStopFeature()
        } withDependencies: {
            $0.transitKeyStore.read = { nil }
        }

        await store.send(.lookupTapped) {
            $0.errorMessage = "No API key configured"
        }
    }

    @Test("save emits saveStop delegate with built draft")
    func saveEmitsDelegate() async {
        let stop = StopInfo(
            stopId: "1_75403", code: "75403", name: "3rd & Pike", routeIds: ["1_100224"]
        )
        let route = RouteInfo(
            routeId: "1_100224", shortName: "12", longName: "Cap Hill", agencyId: "1"
        )

        var initial = AddMonitoredStopFeature.State(sortOrder: 7)
        initial.stopCode = "75403"
        initial.lookedUpStop = stop
        initial.routeOptions = [route]
        initial.selectedRouteId = "1_100224"
        initial.label = "School bus"

        let store = TestStore(initialState: initial) {
            AddMonitoredStopFeature()
        }
        store.exhaustivity = .off

        await store.send(.saveButtonTapped)
        await store.receive(\.delegate.saveStop) { _ in }
    }
}
