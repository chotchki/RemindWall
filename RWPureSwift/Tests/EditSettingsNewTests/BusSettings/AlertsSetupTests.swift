import AppTypes
import ComposableArchitecture
import Dao
import DependenciesTestSupport
import Foundation
import Testing
import TrafficAPI
import TransitAPI

@testable import EditSettingsNew_BusSettings

@MainActor
@Suite("AlertsSetup Feature Tests", .dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
    $0.uuid = .incrementing
    $0.date = .constant(Date(timeIntervalSince1970: 0))
})
struct AlertsSetupTests {

    @Test("onAppear loads the stored API key into the draft")
    func onAppearLoadsKey() async {
        let store = TestStore(initialState: AlertsSetupFeature.State()) {
            AlertsSetupFeature()
        } withDependencies: {
            $0.transitKeyStore.read = { "stored-key" }
        }

        await store.send(.onAppear) {
            $0.apiKeyDraft = "stored-key"
            $0.hasStoredApiKey = true
        }
    }

    @Test("saveApiKey writes through the key store; empty clears it")
    func saveApiKey() async {
        let written = LockIsolated<[String?]>([])
        let store = TestStore(initialState: AlertsSetupFeature.State()) {
            AlertsSetupFeature()
        } withDependencies: {
            $0.transitKeyStore.write = { key in written.withValue { $0.append(key) } }
        }

        await store.send(.apiKeyChanged("abc")) { $0.apiKeyDraft = "abc" }
        await store.send(.saveApiKey) { $0.hasStoredApiKey = true }
        await store.send(.apiKeyChanged("")) { $0.apiKeyDraft = "" }
        await store.send(.saveApiKey) { $0.hasStoredApiKey = false }
        await store.finish()

        #expect(written.value == ["abc", nil])
    }

    @Test("testConnection success and unauthorized surface distinct statuses")
    func testConnection() async {
        let store = TestStore(initialState: {
            var state = AlertsSetupFeature.State()
            state.apiKeyDraft = "abc"
            return state
        }()) {
            AlertsSetupFeature()
        } withDependencies: {
            $0.transitAPI.testConnection = { _ in }
        }

        await store.send(.testConnection) { $0.isTestingConnection = true }
        await store.receive(._connectionResult(true, "Connected")) {
            $0.isTestingConnection = false
            $0.connectionStatus = "Connected"
        }
    }

    @Test("testConnection with no key refuses to call the API")
    func testConnectionWithoutKey() async {
        let store = TestStore(initialState: AlertsSetupFeature.State()) {
            AlertsSetupFeature()
        }

        await store.send(.testConnection) {
            $0.connectionStatus = "Enter an API key first"
        }
    }

    @Test("selecting an origin writes the synced HomeOrigin")
    func originSelection() async {
        let store = TestStore(initialState: AlertsSetupFeature.State()) {
            AlertsSetupFeature()
        } withDependencies: {
            $0.placeSearch.search = { _ in
                [FoundPlace(
                    id: "h", name: "Home", address: "1 Home St",
                    latitude: 47.52, longitude: -122.39
                )]
            }
        }

        await store.send(.originQueryChanged("home")) { $0.originQuery = "home" }
        await store.send(.originSearchTapped) { $0.isSearchingOrigin = true }
        await store.receive(\._originResults) {
            $0.isSearchingOrigin = false
            $0.originResults = [FoundPlace(
                id: "h", name: "Home", address: "1 Home St",
                latitude: 47.52, longitude: -122.39
            )]
        }
        await store.send(.originSelected(FoundPlace(
            id: "h", name: "Home", address: "1 Home St",
            latitude: 47.52, longitude: -122.39
        ))) {
            $0.$homeOrigin.withLock {
                $0 = HomeOrigin(latitude: 47.52, longitude: -122.39, name: "Home")
            }
            $0.originResults = []
            $0.originQuery = ""
        }
        #expect(store.state.homeOrigin?.latitude == 47.52)
        #expect(store.state.homeOrigin?.name == "Home")
    }
}
