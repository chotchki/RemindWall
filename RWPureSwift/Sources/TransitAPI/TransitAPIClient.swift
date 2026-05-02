import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct TransitAPIClient: Sendable {
    /// Returns all upcoming arrivals at the stop. Caller filters by routeId.
    public var fetchArrivals: @Sendable (
        _ apiKey: String,
        _ stopId: String
    ) async throws -> [ArrivalPrediction]

    /// Looks up a stop by its full agency-prefixed id (e.g. "1_75403").
    public var fetchStop: @Sendable (
        _ apiKey: String,
        _ stopId: String
    ) async throws -> StopInfo

    /// Looks up a route by its full agency-prefixed id (e.g. "1_100224").
    public var fetchRoute: @Sendable (
        _ apiKey: String,
        _ routeId: String
    ) async throws -> RouteInfo

    /// Pings the agencies-with-coverage endpoint to validate the key + connectivity.
    public var testConnection: @Sendable (_ apiKey: String) async throws -> Void
}

extension TransitAPIClient: DependencyKey {
    public static let liveValue: Self = {
        let baseURL = URL(string: "https://api.pugetsound.onebusaway.org")!
        let gate = OBARateGate()
        let transport = OBATransport(baseURL: baseURL, gate: gate, session: .shared)

        return Self(
            fetchArrivals: { apiKey, stopId in
                let envelope: OBAEnvelope<OBAArrivalsEntry> = try await transport.get(
                    path: "/api/where/arrivals-and-departures-for-stop/\(stopId).json",
                    apiKey: apiKey
                )
                return envelope.data.entry?.toPredictions() ?? []
            },
            fetchStop: { apiKey, stopId in
                let envelope: OBAEnvelope<OBAStop> = try await transport.get(
                    path: "/api/where/stop/\(stopId).json",
                    apiKey: apiKey
                )
                guard let entry = envelope.data.entry else {
                    throw TransitAPIError.invalidResponse
                }
                return entry.toModel()
            },
            fetchRoute: { apiKey, routeId in
                let envelope: OBAEnvelope<OBARoute> = try await transport.get(
                    path: "/api/where/route/\(routeId).json",
                    apiKey: apiKey
                )
                guard let entry = envelope.data.entry else {
                    throw TransitAPIError.invalidResponse
                }
                return entry.toModel()
            },
            testConnection: { apiKey in
                let _: OBAEnvelope<OBAEmptyEntry> = try await transport.get(
                    path: "/api/where/agencies-with-coverage.json",
                    apiKey: apiKey
                )
            }
        )
    }()

    public static let testValue = Self()

    public static var previewValue: Self {
        Self(
            fetchArrivals: { _, _ in [] },
            fetchStop: { _, _ in
                StopInfo(stopId: "1_75403", code: "75403",
                         name: "3rd Ave & Pike St", routeIds: ["1_100224"])
            },
            fetchRoute: { _, _ in
                RouteInfo(routeId: "1_100224", shortName: "12",
                          longName: "Capitol Hill", agencyId: "1")
            },
            testConnection: { _ in }
        )
    }
}

extension DependencyValues {
    public var transitAPI: TransitAPIClient {
        get { self[TransitAPIClient.self] }
        set { self[TransitAPIClient.self] = newValue }
    }
}

// MARK: - Rate gate

/// Serializes outbound OBA requests so they are spaced ≥110ms apart, comfortably
/// outside the 100ms minimum interval enforced on default keys (which would 401).
actor OBARateGate {
    private var lastRequest: Date = .distantPast
    private let spacing: TimeInterval = 0.110

    func acquire(now: Date = Date()) async {
        let earliest = lastRequest.addingTimeInterval(spacing)
        if now < earliest {
            let wait = earliest.timeIntervalSince(now)
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            lastRequest = Date()
        } else {
            lastRequest = now
        }
    }
}

// MARK: - Transport

struct OBATransport: Sendable {
    let baseURL: URL
    let gate: OBARateGate
    let session: URLSession

    func get<T: Decodable>(path: String, apiKey: String) async throws -> OBAEnvelope<T> {
        await gate.acquire()

        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw TransitAPIError.invalidResponse
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw TransitAPIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TransitAPIError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw TransitAPIError.unauthorized
        case 404: throw TransitAPIError.notFound
        case 429: throw TransitAPIError.rateLimited
        default: throw TransitAPIError.network("HTTP \(http.statusCode)")
        }

        do {
            return try OBAEnvelope<T>.decode(from: data)
        } catch let err as TransitAPIError {
            throw err
        } catch {
            throw TransitAPIError.decoding(error.localizedDescription)
        }
    }
}

// MARK: - Wire format

struct OBAEnvelope<Entry: Decodable & Sendable>: Decodable, Sendable {
    let code: Int
    let data: OBAData<Entry>

    static func decode(from data: Data) throws -> OBAEnvelope<Entry> {
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(OBAEnvelope<Entry>.self, from: data)
        switch envelope.code {
        case 200..<300: return envelope
        case 401: throw TransitAPIError.unauthorized
        case 404: throw TransitAPIError.notFound
        default: throw TransitAPIError.network("OBA code \(envelope.code)")
        }
    }
}

struct OBAData<Entry: Decodable & Sendable>: Decodable, Sendable {
    let entry: Entry?
}

struct OBAEmptyEntry: Decodable, Sendable {}

struct OBAArrivalsEntry: Decodable, Sendable {
    let stopId: String
    let arrivalsAndDepartures: [OBAArrivalAndDeparture]
}

struct OBAArrivalAndDeparture: Decodable, Sendable {
    let routeId: String
    let tripId: String
    let tripHeadsign: String?
    let scheduledArrivalTime: Int64
    let predictedArrivalTime: Int64
    let predicted: Bool
    let lastUpdateTime: Int64?
}

extension OBAArrivalsEntry {
    func toPredictions() -> [ArrivalPrediction] {
        arrivalsAndDepartures.map { ad in
            ArrivalPrediction(
                stopId: stopId,
                routeId: ad.routeId,
                tripId: ad.tripId,
                tripHeadsign: ad.tripHeadsign ?? "",
                scheduledArrival: dateOrNil(ad.scheduledArrivalTime),
                predictedArrival: dateOrNil(ad.predictedArrivalTime),
                isPredicted: ad.predicted,
                lastUpdate: dateOrNil(ad.lastUpdateTime ?? 0)
            )
        }
    }
}

struct OBAStop: Decodable, Sendable {
    let id: String
    let code: String?
    let name: String
    let routeIds: [String]

    func toModel() -> StopInfo {
        StopInfo(stopId: id, code: code ?? "", name: name, routeIds: routeIds)
    }
}

struct OBARoute: Decodable, Sendable {
    let id: String
    let shortName: String?
    let longName: String?
    let agencyId: String

    func toModel() -> RouteInfo {
        RouteInfo(
            routeId: id,
            shortName: shortName ?? "",
            longName: longName ?? "",
            agencyId: agencyId
        )
    }
}

private func dateOrNil(_ ms: Int64) -> Date? {
    guard ms > 0 else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
}
