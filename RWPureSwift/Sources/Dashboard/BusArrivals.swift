import AppTypes
import ComposableArchitecture
import Dao
import Dependencies
import Foundation
import SQLiteData
import Tagged
import TransitAPI

public struct DisplayArrival: Equatable, Identifiable, Sendable {
    public let id: MonitoredStop.ID
    public let label: String
    public let routeShortName: String
    public let etaText: String
    public let etaSeconds: TimeInterval
    public let isLate: Bool
    public let isLive: Bool
}

@Reducer
public struct BusArrivalsFeature: Sendable {
    @Dependency(\.transitAPI) var transitAPI
    @Dependency(\.transitKeyStore) var transitKeyStore
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    @Dependency(\.calendar) var calendar

    static let refreshInterval = Duration.seconds(30)
    static let lateThresholdSeconds: TimeInterval = 90

    @ObservableState
    public struct State: Equatable {
        @FetchAll(MonitoredStop.none)
        public var monitoredStops: [MonitoredStop]

        public var arrivals: [DisplayArrival] = []
        public var lastError: String? = nil

        /// One card per monitored stop; a fetch failure with nothing to show
        /// collapses to a single error chip (lowest priority - family info,
        /// not devops).
        public var railCards: [RailCard] {
            var cards = arrivals.map { arrival in
                RailCard(
                    id: "bus-\(arrival.id.rawValue.uuidString)",
                    priority: arrival.isLate ? .lateBus : .onTimeBus,
                    etaSeconds: arrival.etaSeconds,
                    content: .transit(
                        route: arrival.routeShortName,
                        label: arrival.label,
                        etaText: arrival.etaText,
                        isLate: arrival.isLate,
                        isLive: arrival.isLive
                    )
                )
            }
            if arrivals.isEmpty, let lastError {
                cards.append(RailCard(
                    id: "bus-error",
                    priority: .errorChip,
                    content: .errorChip(message: "Cannot reach transit API: \(lastError)")
                ))
            }
            return cards
        }

        public init() {
            self._monitoredStops = FetchAll(MonitoredStop.all.order(by: \.sortOrder))
        }
    }

    public enum Action: Equatable {
        case startMonitoring
        case tick
        case _arrivalsLoaded([DisplayArrival], error: String?)
    }

    enum CancelID { case busLoop }

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
                .cancellable(id: CancelID.busLoop, cancelInFlight: true)

            case .tick:
                // Per-watch gating (TR1.7): each stop carries its own window
                // and toggle; nil window means the mode default.
                let active = state.monitoredStops.filter { stop in
                    stop.enabled
                        && (stop.window ?? .default).isInWindow(date: now, calendar: calendar)
                }
                guard let key = transitKeyStore.read(), !active.isEmpty else {
                    return .send(._arrivalsLoaded([], error: nil))
                }
                let uniqueStopIds = Array(Set(active.map(\.stopId)))
                return .run { [transitAPI, now] send in
                    do {
                        let byStop = try await fetchAllArrivals(
                            api: transitAPI, key: key, stopIds: uniqueStopIds
                        )
                        let display = active.compactMap { stop -> DisplayArrival? in
                            let arrivals = (byStop[stop.stopId] ?? [])
                                .filter { $0.routeId == stop.routeId }
                                .sorted {
                                    ($0.effectiveArrival ?? .distantFuture)
                                        < ($1.effectiveArrival ?? .distantFuture)
                                }
                            return makeDisplay(stop: stop, soonest: arrivals.first, now: now)
                        }
                        await send(._arrivalsLoaded(display, error: nil))
                    } catch {
                        await send(._arrivalsLoaded([], error: "\(error)"))
                    }
                }

            case let ._arrivalsLoaded(arrivals, error):
                state.arrivals = arrivals
                state.lastError = error
                return .none
            }
        }
    }
}

private func fetchAllArrivals(
    api: TransitAPIClient,
    key: String,
    stopIds: [String]
) async throws -> [String: [ArrivalPrediction]] {
    try await withThrowingTaskGroup(of: (String, [ArrivalPrediction]).self) { group in
        for stopId in stopIds {
            group.addTask {
                let arrivals = try await api.fetchArrivals(apiKey: key, stopId: stopId)
                return (stopId, arrivals)
            }
        }
        var result: [String: [ArrivalPrediction]] = [:]
        for try await (stopId, arrivals) in group {
            result[stopId] = arrivals
        }
        return result
    }
}

func makeDisplay(
    stop: MonitoredStop,
    soonest: ArrivalPrediction?,
    now: Date
) -> DisplayArrival? {
    guard let arrival = soonest, let when = arrival.effectiveArrival else {
        return nil
    }
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .brief
    formatter.allowedUnits = [.hour, .minute]
    let etaCore = formatter.string(from: now, to: when) ?? ""
    let etaText: String
    if arrival.isLive {
        etaText = etaCore.isEmpty ? "now" : etaCore
    } else {
        etaText = etaCore.isEmpty ? "scheduled" : "scheduled \(etaCore)"
    }
    let isLate: Bool = {
        guard let lateness = arrival.lateness else { return false }
        return lateness > BusArrivalsFeature.lateThresholdSeconds
    }()
    return DisplayArrival(
        id: stop.id,
        label: stop.label,
        routeShortName: stop.routeShortName,
        etaText: etaText,
        etaSeconds: when.timeIntervalSince(now),
        isLate: isLate,
        isLive: arrival.isLive
    )
}
