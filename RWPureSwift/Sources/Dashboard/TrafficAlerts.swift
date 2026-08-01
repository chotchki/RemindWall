import AppTypes
import ComposableArchitecture
import Dao
import Dependencies
import Foundation
import SQLiteData
import Tagged
import TrafficAPI

public struct DisplayRoute: Equatable, Identifiable, Sendable {
    public let id: MonitoredRoute.ID
    public let label: String
    public let etaMinutes: Int
    public let normalMinutes: Int
    public let etaSeconds: TimeInterval
    public let isLate: Bool
}

@Reducer
public struct TrafficAlertsFeature: Sendable {
    @Dependency(\.trafficAPI) var trafficAPI
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    @Dependency(\.calendar) var calendar

    /// Traffic shifts over minutes, not seconds - and MKDirections is not a
    /// firehose to point a 30s timer at.
    static let refreshInterval = Duration.seconds(60 * 5)
    /// Late when the live ETA exceeds the route's normal by this much.
    static let lateThresholdMinutes = 5

    @ObservableState
    public struct State: Equatable {
        @Shared(.syncedSetting(HOME_ORIGIN_SETTING_KEY)) public var homeOrigin: HomeOrigin?

        @FetchAll(MonitoredRoute.none)
        public var routes: [MonitoredRoute]

        public var displayRoutes: [DisplayRoute] = []
        public var lastError: String? = nil

        /// One card per route; a fetch failure with nothing to show collapses
        /// to a single error chip, mirroring the bus rules (stale beats noise).
        public var railCards: [RailCard] {
            var cards = displayRoutes.map { route in
                RailCard(
                    id: "drive-\(route.id.rawValue.uuidString)",
                    priority: route.isLate ? .slowRoute : .onTimeRoute,
                    etaSeconds: route.etaSeconds,
                    content: .drive(
                        label: route.label,
                        etaText: "\(route.etaMinutes) min",
                        isLate: route.isLate
                    )
                )
            }
            if displayRoutes.isEmpty, let lastError {
                cards.append(RailCard(
                    id: "drive-error",
                    priority: .errorChip,
                    content: .errorChip(message: "Drive times unavailable: \(lastError)")
                ))
            }
            return cards
        }

        public init() {
            self._routes = FetchAll(MonitoredRoute.all.order(by: \.sortOrder))
        }
    }

    public enum Action: Equatable {
        case startMonitoring
        case tick
        case _routesLoaded([DisplayRoute], error: String?)
    }

    enum CancelID { case trafficLoop, fetch }

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .startMonitoring:
                return .run { send in
                    await send(.tick)
                    for await _ in clock.timer(interval: Self.refreshInterval) {
                        await send(.tick)
                    }
                }
                .cancellable(id: CancelID.trafficLoop, cancelInFlight: true)

            case .tick:
                // Per-watch gating (TR1.7): each route carries its own window
                // and toggle; nil window means the mode default.
                let active = state.routes.filter { route in
                    route.enabled
                        && (route.window ?? .default).isInWindow(date: now, calendar: calendar)
                }
                guard !active.isEmpty else {
                    return .send(._routesLoaded([], error: nil))
                }
                guard
                    let origin = state.homeOrigin,
                    let latitude = origin.latitude,
                    let longitude = origin.longitude
                else {
                    // Routes exist but no origin: TR1.4's Setup screen is the
                    // fix; until then say so instead of a blank rail.
                    return .send(._routesLoaded([], error: "home origin not set"))
                }
                let originPoint = RoutePoint(latitude: latitude, longitude: longitude)
                return .run { [trafficAPI] send in
                    do {
                        var display: [DisplayRoute] = []
                        for route in active {
                            let eta = try await trafficAPI.calculateETA(
                                originPoint,
                                RoutePoint(
                                    latitude: route.destinationLatitude,
                                    longitude: route.destinationLongitude
                                )
                            )
                            display.append(makeDisplayRoute(route: route, eta: eta))
                        }
                        await send(._routesLoaded(display, error: nil))
                    } catch {
                        await send(._routesLoaded([], error: "\(error)"))
                    }
                }
                .cancellable(id: CancelID.fetch, cancelInFlight: true)

            case let ._routesLoaded(display, error):
                state.displayRoutes = display
                state.lastError = error
                return .none
            }
        }
    }
}

func makeDisplayRoute(route: MonitoredRoute, eta: DriveETA) -> DisplayRoute {
    let minutes = eta.expectedMinutes
    return DisplayRoute(
        id: route.id,
        label: route.label,
        etaMinutes: minutes,
        normalMinutes: route.normalMinutes,
        etaSeconds: eta.expectedTravelTime,
        isLate: minutes > route.normalMinutes + TrafficAlertsFeature.lateThresholdMinutes
    )
}
