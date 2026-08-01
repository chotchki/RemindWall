import CoreLocation
import Dependencies
import DependenciesMacros
import Foundation
import MapKit

/// One MKLocalSearch hit as plain values, for destination and home-origin
/// picking in the alerts settings.
public struct FoundPlace: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let address: String
    public let latitude: Double
    public let longitude: Double

    public init(id: String, name: String, address: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }
}

@DependencyClient
public struct PlaceSearchClient: Sendable {
    /// Natural-language place lookup via Apple Maps.
    public var search: @Sendable (_ query: String) async throws -> [FoundPlace]
}

extension PlaceSearchClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            search: { query in
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = query
                let response = try await MKLocalSearch(request: request).start()
                return response.mapItems.compactMap { item in
                    guard let name = item.name else { return nil }
                    let coordinate = item.placemark.coordinate
                    return FoundPlace(
                        id: "\(name)|\(coordinate.latitude)|\(coordinate.longitude)",
                        name: name,
                        address: item.placemark.title ?? "",
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    )
                }
            }
        )
    }
}

extension PlaceSearchClient: TestDependencyKey {
    public static let testValue = Self()

    public static var previewValue: Self {
        Self(
            search: { query in
                [
                    FoundPlace(
                        id: "preview-1", name: "Maple Elementary",
                        address: "402 School Rd, Seattle",
                        latitude: 47.5423, longitude: -122.3866
                    ),
                    FoundPlace(
                        id: "preview-2", name: "\(query) Learning Ctr",
                        address: "98 Pine Ave, Renton",
                        latitude: 47.48, longitude: -122.2
                    ),
                ]
            }
        )
    }
}

extension DependencyValues {
    public var placeSearch: PlaceSearchClient {
        get { self[PlaceSearchClient.self] }
        set { self[PlaceSearchClient.self] = newValue }
    }
}
