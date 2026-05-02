import Foundation

public struct StopInfo: Equatable, Sendable {
    public let stopId: String
    public let code: String
    public let name: String
    public let routeIds: [String]

    public init(stopId: String, code: String, name: String, routeIds: [String]) {
        self.stopId = stopId
        self.code = code
        self.name = name
        self.routeIds = routeIds
    }
}

public struct RouteInfo: Equatable, Sendable {
    public let routeId: String
    public let shortName: String
    public let longName: String
    public let agencyId: String

    public init(routeId: String, shortName: String, longName: String, agencyId: String) {
        self.routeId = routeId
        self.shortName = shortName
        self.longName = longName
        self.agencyId = agencyId
    }
}

public struct ArrivalPrediction: Equatable, Sendable {
    public let stopId: String
    public let routeId: String
    public let tripId: String
    public let tripHeadsign: String
    public let scheduledArrival: Date?
    public let predictedArrival: Date?
    public let isPredicted: Bool
    public let lastUpdate: Date?

    public init(
        stopId: String,
        routeId: String,
        tripId: String,
        tripHeadsign: String,
        scheduledArrival: Date?,
        predictedArrival: Date?,
        isPredicted: Bool,
        lastUpdate: Date?
    ) {
        self.stopId = stopId
        self.routeId = routeId
        self.tripId = tripId
        self.tripHeadsign = tripHeadsign
        self.scheduledArrival = scheduledArrival
        self.predictedArrival = predictedArrival
        self.isPredicted = isPredicted
        self.lastUpdate = lastUpdate
    }

    public var effectiveArrival: Date? { predictedArrival ?? scheduledArrival }

    public var isLive: Bool { isPredicted && predictedArrival != nil }

    public var lateness: TimeInterval? {
        guard let p = predictedArrival, let s = scheduledArrival else { return nil }
        return p.timeIntervalSince(s)
    }
}

public enum TransitAPIError: Error, Equatable, Sendable {
    case unauthorized
    case rateLimited
    case notFound
    case invalidResponse
    case network(String)
    case decoding(String)
}
