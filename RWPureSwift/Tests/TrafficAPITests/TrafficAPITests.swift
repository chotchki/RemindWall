import Foundation
import Testing

@testable import TrafficAPI

@Suite("TrafficAPI Tests")
struct TrafficAPITests {
    @Test("expectedMinutes rounds UP - late math must never flatter the drive")
    func minutesRoundUp() {
        #expect(DriveETA(expectedTravelTime: 17 * 60 + 10, distanceMeters: 0).expectedMinutes == 18)
        #expect(DriveETA(expectedTravelTime: 18 * 60, distanceMeters: 0).expectedMinutes == 18)
        #expect(DriveETA(expectedTravelTime: 30, distanceMeters: 0).expectedMinutes == 1)
        #expect(DriveETA(expectedTravelTime: 0, distanceMeters: 0).expectedMinutes == 0)
    }

    @Test("preview client returns a plausible drive")
    func previewShape() async throws {
        let eta = try await TrafficAPIClient.previewValue.calculateETA(
            RoutePoint(latitude: 47.6, longitude: -122.3),
            RoutePoint(latitude: 47.5, longitude: -122.2)
        )
        #expect(eta.expectedMinutes == 18)
    }
}
