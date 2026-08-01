import CoreLocation
import Dependencies
import DependenciesMacros
import Foundation
import MapKit

/// A stored coordinate pair - matches MonitoredRoute's lat/lon columns so
/// nothing MapKit-typed leaks into the database layer.
public struct RoutePoint: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct DriveETA: Equatable, Sendable {
    public let expectedTravelTime: TimeInterval
    public let distanceMeters: Double

    public init(expectedTravelTime: TimeInterval, distanceMeters: Double) {
        self.expectedTravelTime = expectedTravelTime
        self.distanceMeters = distanceMeters
    }

    /// Whole minutes, rounded UP - "18 min" that arrives in 17:10 is honest,
    /// "17 min" that arrives in 17:50 makes you late.
    public var expectedMinutes: Int {
        Int((expectedTravelTime / 60).rounded(.up))
    }
}

public enum TrafficAPIError: Error, Equatable, Sendable {
    case noRoute
    case network(String)
}

@DependencyClient
public struct TrafficAPIClient: Sendable {
    /// Traffic-aware drive time via Apple Maps. No key store - MapKit rides
    /// the app's own entitlement, which is the whole reason TR1 picked it.
    public var calculateETA: @Sendable (
        _ origin: RoutePoint,
        _ destination: RoutePoint
    ) async throws -> DriveETA
}

extension TrafficAPIClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            calculateETA: { origin, destination in
                let request = MKDirections.Request()
                request.source = MKMapItem(
                    placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
                        latitude: origin.latitude, longitude: origin.longitude
                    ))
                )
                request.destination = MKMapItem(
                    placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
                        latitude: destination.latitude, longitude: destination.longitude
                    ))
                )
                request.transportType = .automobile
                do {
                    let response = try await MKDirections(request: request).calculateETA()
                    return DriveETA(
                        expectedTravelTime: response.expectedTravelTime,
                        distanceMeters: response.distance
                    )
                } catch let error as MKError where error.code == .directionsNotFound {
                    throw TrafficAPIError.noRoute
                } catch {
                    throw TrafficAPIError.network(error.localizedDescription)
                }
            }
        )
    }
}

extension TrafficAPIClient: TestDependencyKey {
    public static let testValue = Self()

    public static var previewValue: Self {
        Self(
            calculateETA: { _, _ in
                DriveETA(expectedTravelTime: 18 * 60, distanceMeters: 9200)
            }
        )
    }
}

extension DependencyValues {
    public var trafficAPI: TrafficAPIClient {
        get { self[TrafficAPIClient.self] }
        set { self[TrafficAPIClient.self] = newValue }
    }
}
