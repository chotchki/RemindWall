import AppTypes
import ComposableArchitecture
import Dao
import DependenciesTestSupport
import Foundation
import Testing
import TransitAPI

@testable import EditSettingsNew_BusSettings

@MainActor
@Suite("BusSettings Feature Tests", .dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
    $0.uuid = .incrementing
})
struct BusSettingsFeatureTests {

    @Test("onAppear loads stored API key into draft")
    func onAppearLoadsKey() async {
        let store = TestStore(initialState: BusSettingsFeature.State()) {
            BusSettingsFeature()
        } withDependencies: {
            $0.transitKeyStore.read = { "stored-key" }
            $0.transitKeyStore.write = { _ in }
        }

        await store.send(.onAppear) {
            $0.apiKeyDraft = "stored-key"
            $0.hasStoredApiKey = true
        }
    }

    @Test("enabled toggle on initializes default window")
    func enabledTogglePopulatesDefaultWindow() async {
        let store = TestStore(initialState: BusSettingsFeature.State()) {
            BusSettingsFeature()
        }

        await store.send(.enabledToggled(true)) {
            $0.$enabled.withLock { $0 = true }
            $0.$window.withLock { $0 = .default }
        }
    }

    @Test("toggle weekday adds and removes day")
    func toggleWeekday() async {
        let initial: BusSettingsFeature.State = {
            var s = BusSettingsFeature.State()
            s.$window.withLock { $0 = .default }
            return s
        }()

        let store = TestStore(initialState: initial) {
            BusSettingsFeature()
        }

        // Default has Mon–Fri; toggling Saturday adds it.
        await store.send(.toggleWeekday(.Saturday)) {
            $0.$window.withLock {
                $0 = ($0 ?? .default).withWeekdays(
                    [.Monday, .Tuesday, .Wednesday, .Thursday, .Friday, .Saturday]
                )
            }
        }

        // Toggling Saturday again removes it.
        await store.send(.toggleWeekday(.Saturday)) {
            $0.$window.withLock {
                $0 = ($0 ?? .default).withWeekdays(
                    [.Monday, .Tuesday, .Wednesday, .Thursday, .Friday]
                )
            }
        }
    }

    @Test("setStartTime updates window without losing weekdays")
    func setStartTime() async {
        let initial: BusSettingsFeature.State = {
            var s = BusSettingsFeature.State()
            s.$window.withLock { $0 = .default }
            return s
        }()

        let store = TestStore(initialState: initial) {
            BusSettingsFeature()
        }

        await store.send(.setStartTime(hour: 7, minute: 0)) {
            $0.$window.withLock {
                $0 = ($0 ?? .default).withStart(hour: 7, minute: 0)
            }
        }
    }

    @Test("saveApiKey writes to keychain via dependency")
    func saveApiKeyWritesToKeychain() async {
        let written = LockIsolated<String?>(nil)

        var initial = BusSettingsFeature.State()
        initial.apiKeyDraft = "abc123"

        let store = TestStore(initialState: initial) {
            BusSettingsFeature()
        } withDependencies: {
            $0.transitKeyStore.write = { written.setValue($0) }
        }

        await store.send(.saveApiKey) {
            $0.hasStoredApiKey = true
        }
        await store.finish()

        #expect(written.value == "abc123")
    }

    @Test("saveApiKey with empty draft writes nil and clears stored flag")
    func saveApiKeyEmptyClearsKeychain() async {
        let written = LockIsolated<String?>("not-nil")

        var initial = BusSettingsFeature.State()
        initial.apiKeyDraft = ""
        initial.hasStoredApiKey = true

        let store = TestStore(initialState: initial) {
            BusSettingsFeature()
        } withDependencies: {
            $0.transitKeyStore.write = { written.setValue($0) }
        }

        await store.send(.saveApiKey) {
            $0.hasStoredApiKey = false
        }
        await store.finish()

        #expect(written.value == nil)
    }

    @Test("testConnection success sets connected status")
    func testConnectionSuccess() async {
        var initial = BusSettingsFeature.State()
        initial.apiKeyDraft = "valid"

        let store = TestStore(initialState: initial) {
            BusSettingsFeature()
        } withDependencies: {
            $0.transitAPI.testConnection = { _ in }
        }

        await store.send(.testConnection) {
            $0.isTestingConnection = true
        }
        await store.receive(\._connectionResult) {
            $0.isTestingConnection = false
            $0.connectionStatus = "Connected"
        }
    }

    @Test("testConnection unauthorized surfaces specific message")
    func testConnectionUnauthorized() async {
        var initial = BusSettingsFeature.State()
        initial.apiKeyDraft = "bogus"

        let store = TestStore(initialState: initial) {
            BusSettingsFeature()
        } withDependencies: {
            $0.transitAPI.testConnection = { _ in throw TransitAPIError.unauthorized }
        }

        await store.send(.testConnection) {
            $0.isTestingConnection = true
        }
        await store.receive(\._connectionResult) {
            $0.isTestingConnection = false
            $0.connectionStatus = "API key was rejected"
        }
    }

    @Test("testConnection with empty draft refuses to call api")
    func testConnectionWithoutKey() async {
        let store = TestStore(initialState: BusSettingsFeature.State()) {
            BusSettingsFeature()
        }

        await store.send(.testConnection) {
            $0.connectionStatus = "Enter an API key first"
        }
    }
}
