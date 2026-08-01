import Dependencies
import Foundation
import Testing

@testable import HomeKitAsync

@Suite("HomeKitAsync Tests")
struct HomeKitAsyncTests {
    private func status(level: Int?, isLow: Bool) -> BatteryStatus {
        BatteryStatus(
            id: UUID(0),
            accessoryName: "Sensor",
            roomName: nil,
            levelPercent: level,
            isLow: isLow
        )
    }

    @Test("The accessory's own low flag alerts regardless of level")
    func lowFlagAlerts() {
        #expect(status(level: 90, isLow: true).isAlertable(belowPercent: 20))
    }

    @Test("A level under the threshold alerts without the flag")
    func thresholdAlerts() {
        #expect(status(level: 12, isLow: false).isAlertable(belowPercent: 20))
    }

    @Test("At or above the threshold with no flag stays quiet")
    func aboveThresholdQuiet() {
        #expect(!status(level: 20, isLow: false).isAlertable(belowPercent: 20))
        #expect(!status(level: 95, isLow: false).isAlertable(belowPercent: 20))
    }

    @Test("An unreadable level never alerts on its own")
    func unreadableLevelQuiet() {
        #expect(!status(level: nil, isLow: false).isAlertable(belowPercent: 20))
        #expect(status(level: nil, isLow: true).isAlertable(belowPercent: 20))
    }

    @Test("The preview client ships a genuinely-low battery for UI work")
    func previewShape() async {
        let preview = HomeKitAsyncClient.previewValue
        let statuses = await preview.batteryStatuses()
        #expect(!statuses.isEmpty)
        #expect(statuses.contains { $0.isAlertable(belowPercent: 20) })
        #expect(await preview.authorizationStatus() == .authorized)
    }
}
