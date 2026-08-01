import AppTypes
import ComposableArchitecture
import Dao
import DependenciesTestSupport
import Foundation
import HomeKitAsync
import Testing

@testable import Dashboard

@MainActor
@Suite("BatteryAlerts Feature Tests", .dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
    $0.uuid = .incrementing
    // .syncedSetting stamps lastModified when tests flip enabled/threshold.
    $0.date = .constant(Date(timeIntervalSince1970: 0))
})
struct BatteryAlertsTests {
    private func status(
        _ name: String,
        level: Int?,
        isLow: Bool = false
    ) -> BatteryStatus {
        BatteryStatus(
            id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", abs(name.hashValue % 1_000_000)))")!,
            accessoryName: name,
            roomName: nil,
            levelPercent: level,
            isLow: isLow
        )
    }

    @Test("startMonitoring ticks immediately, then every 30 minutes")
    func pollLoop() async {
        let clock = TestClock()
        let fetchCount = LockIsolated(0)

        let store = TestStore(initialState: BatteryAlertsFeature.State()) {
            BatteryAlertsFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.homeKitAsync.batteryStatuses = {
                fetchCount.withValue { $0 += 1 }
                return []
            }
        }
        store.exhaustivity = .off
        // Through the store, not before it - pre-store shared mutations
        // surface as phantom changes on the first send.
        store.state.$enabled.withLock { $0 = true }

        await store.send(.startMonitoring)
        await store.receive(\._statusesLoaded)
        #expect(fetchCount.value == 1)

        await clock.advance(by: .seconds(60 * 30))
        await store.receive(\._statusesLoaded)
        #expect(fetchCount.value == 2)

        // Restart replaces the loop (cancelInFlight) rather than doubling it.
        await store.send(.startMonitoring)
        await store.receive(\._statusesLoaded)
        #expect(fetchCount.value == 3)
    }

    @Test("disabled ticks never touch HomeKit and clear stale statuses")
    func disabledTick() async {
        let store = TestStore(initialState: {
            var state = BatteryAlertsFeature.State()
            state.statuses = [status("Old Sensor", level: 5)]
            return state
        }()) {
            BatteryAlertsFeature()
        }

        // homeKitAsync deliberately unstubbed: a call would fail the test.
        await store.send(.tick)
        await store.receive(\._statusesLoaded) {
            $0.statuses = []
        }
    }

    @Test("chips surface only alertable batteries, honoring the synced threshold")
    func thresholdFilter() async {
        var state = BatteryAlertsFeature.State()
        state.$enabled.withLock { $0 = true }
        state.$thresholdPercent.withLock { $0 = 20 }
        state.statuses = [
            status("Front Door Sensor", level: 8),
            status("Thermostat", level: 76),
            status("Motion Sensor", level: 19),
        ]

        #expect(state.ambientChips.map(\.text) == [
            "Front Door Sensor · 8%",
            "Motion Sensor · 19%",
        ])

        // Tighten the threshold and the 19% chip disappears - the filter
        // reads the SYNCED knob, not a baked-in constant.
        state.$thresholdPercent.withLock { $0 = 10 }
        #expect(state.ambientChips.map(\.text) == ["Front Door Sensor · 8%"])
    }

    @Test("the accessory's own low flag beats a healthy-looking level")
    func lowFlagChip() async {
        var state = BatteryAlertsFeature.State()
        state.$enabled.withLock { $0 = true }
        state.statuses = [status("Water Sensor", level: nil, isLow: true)]

        #expect(state.ambientChips.map(\.text) == ["Water Sensor · low"])
    }

    @Test("disabled means no chips even with alertable statuses on hand")
    func disabledNoChips() async {
        var state = BatteryAlertsFeature.State()
        state.statuses = [status("Front Door Sensor", level: 8)]

        #expect(state.ambientChips.isEmpty)
    }

    @Test("chips sort lowest level first")
    func chipOrdering() async {
        var state = BatteryAlertsFeature.State()
        state.$enabled.withLock { $0 = true }
        state.statuses = [
            status("B Sensor", level: 15),
            status("A Sensor", level: 15),
            status("C Sensor", level: 3),
        ]

        #expect(state.ambientChips.map(\.text) == [
            "C Sensor · 3%",
            "A Sensor · 15%",
            "B Sensor · 15%",
        ])
    }
}
