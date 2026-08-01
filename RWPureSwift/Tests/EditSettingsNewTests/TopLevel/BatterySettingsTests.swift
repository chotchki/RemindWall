import AppTypes
import ComposableArchitecture
import Dao
import DependenciesTestSupport
import Foundation
import HomeKitAsync
import Testing

@testable import EditSettingsNew_TopLevel

@MainActor
@Suite("BatterySettings Feature Tests", .dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
    $0.uuid = .incrementing
    $0.date = .constant(Date(timeIntervalSince1970: 0))
})
struct BatterySettingsTests {

    @Test("threshold writes and clamps to 5-50")
    func threshold() async {
        let store = TestStore(initialState: BatterySettingsFeature.State()) {
            BatterySettingsFeature()
        }

        await store.send(.thresholdChanged(35)) {
            $0.$thresholdPercent.withLock { $0 = 35 }
        }
        await store.send(.thresholdChanged(0)) {
            $0.$thresholdPercent.withLock { $0 = 5 }
        }
        await store.send(.thresholdChanged(95)) {
            $0.$thresholdPercent.withLock { $0 = 50 }
        }
    }

    @Test("window toggle flips between nil (always) and the default window")
    func windowToggle() async {
        let store = TestStore(initialState: BatterySettingsFeature.State()) {
            BatterySettingsFeature()
        }

        await store.send(.windowedToggled(true)) {
            $0.$window.withLock { $0 = .default }
        }
        await store.send(.setWindowStart(hour: 8, minute: 30)) {
            $0.$window.withLock { $0 = AlertWindow.default.withStart(hour: 8, minute: 30) }
        }
        await store.send(.windowedToggled(false)) {
            $0.$window.withLock { $0 = nil }
        }
    }

    @Test("refresh loads and sorts discovered batteries lowest-first")
    func refreshDiscovers() async {
        let store = TestStore(initialState: BatterySettingsFeature.State()) {
            BatterySettingsFeature()
        } withDependencies: {
            $0.homeKitAsync.batteryStatuses = {
                [
                    BatteryStatus(id: UUID(0), accessoryName: "Thermostat", roomName: "Bedroom", levelPercent: 76, isLow: false),
                    BatteryStatus(id: UUID(1), accessoryName: "Door Sensor", roomName: "Entry", levelPercent: 8, isLow: true),
                ]
            }
        }

        await store.send(.refreshBatteries) {
            $0.isLoadingBatteries = true
        }
        await store.receive(\._batteriesLoaded) {
            $0.isLoadingBatteries = false
            $0.discovered = [
                BatteryStatus(id: UUID(1), accessoryName: "Door Sensor", roomName: "Entry", levelPercent: 8, isLow: true),
                BatteryStatus(id: UUID(0), accessoryName: "Thermostat", roomName: "Bedroom", levelPercent: 76, isLow: false),
            ]
        }
    }

    @Test("onAppear kicks off a browser refresh")
    func onAppearRefreshes() async {
        let store = TestStore(initialState: BatterySettingsFeature.State()) {
            BatterySettingsFeature()
        } withDependencies: {
            $0.homeKitAsync.batteryStatuses = { [] }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\._batteriesLoaded)
    }
}
