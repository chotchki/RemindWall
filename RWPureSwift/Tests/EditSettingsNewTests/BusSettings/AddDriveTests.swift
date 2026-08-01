import ComposableArchitecture
import Dao
import DependenciesTestSupport
import Foundation
import Testing
import TrafficAPI

@testable import EditSettingsNew_BusSettings

@MainActor
@Suite("AddDrive Feature Tests", .dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
    $0.uuid = .incrementing
})
struct AddDriveTests {

    @Test("search loads results; selecting fills the label")
    func searchAndSelect() async {
        let store = TestStore(initialState: AddDriveFeature.State(sortOrder: 0)) {
            AddDriveFeature()
        } withDependencies: {
            $0.placeSearch.search = { _ in [schoolPlace] }
        }

        await store.send(.queryChanged("maple")) {
            $0.query = "maple"
        }
        await store.send(.searchTapped) {
            $0.isSearching = true
        }
        await store.receive(\._resultsLoaded) {
            $0.isSearching = false
            $0.results = [schoolPlace]
        }
        await store.send(.placeSelected(schoolPlace)) {
            $0.selectedPlace = schoolPlace
            $0.label = "Maple Elementary"
        }
        #expect(store.state.canSave)
    }

    @Test("save emits a draft carrying coords, label and normal minutes")
    func saveDraft() async {
        var state = AddDriveFeature.State(sortOrder: 3)
        state.selectedPlace = schoolPlace
        state.label = "School run"
        state.normalMinutes = 12

        let store = TestStore(initialState: state) {
            AddDriveFeature()
        }
        store.exhaustivity = .off

        await store.send(.saveButtonTapped)
        await store.receive(.delegate(.saveRoute(
            MonitoredRoute.Draft(
                label: "School run",
                destinationLatitude: 47.5423, destinationLongitude: -122.3866,
                destinationName: "Maple Elementary", normalMinutes: 12, sortOrder: 3,
                window: nil, enabled: true
            )
        )))
    }

    @Test("a failed search surfaces the error, an empty one says so")
    func searchFailures() async {
        let store = TestStore(initialState: AddDriveFeature.State(sortOrder: 0)) {
            AddDriveFeature()
        } withDependencies: {
            $0.placeSearch.search = { _ in [] }
        }

        await store.send(.queryChanged("nowhere")) { $0.query = "nowhere" }
        await store.send(.searchTapped) { $0.isSearching = true }
        await store.receive(\._resultsLoaded) {
            $0.isSearching = false
            $0.errorMessage = "No places found"
        }
    }
}

private let schoolPlace = FoundPlace(
    id: "p1", name: "Maple Elementary", address: "402 School Rd, Seattle",
    latitude: 47.5423, longitude: -122.3866
)
