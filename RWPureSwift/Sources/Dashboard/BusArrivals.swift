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
        @Shared(.appStorage(BUS_ALERTS_ENABLED_SETTING_KEY)) public var enabled: Bool = false
        @Shared(.appStorage(BUS_WINDOW_SETTING_KEY)) public var window: BusWindow?

        @FetchAll(MonitoredStop.none)
        public var monitoredStops: [MonitoredStop]

        public var arrivals: [DisplayArrival] = []
        public var inWindow: Bool = false
        public var lastError: String? = nil

        public init() {
            self._monitoredStops = FetchAll(MonitoredStop.all.order(by: \.sortOrder))
        }
    }

    public enum Action: Equatable {
        case startMonitoring
        case tick
        case _arrivalsLoaded([DisplayArrival], inWindow: Bool, error: String?)
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
                let inWindow = state.window?.isInWindow(date: now, calendar: calendar) ?? false
                guard state.enabled, inWindow,
                      let key = transitKeyStore.read(),
                      !state.monitoredStops.isEmpty
                else {
                    return .send(._arrivalsLoaded([], inWindow: inWindow, error: nil))
                }
                let stops = state.monitoredStops
                let uniqueStopIds = Array(Set(stops.map(\.stopId)))
                return .run { [transitAPI, now] send in
                    do {
                        let byStop = try await fetchAllArrivals(
                            api: transitAPI, key: key, stopIds: uniqueStopIds
                        )
                        let display = stops.compactMap { stop -> DisplayArrival? in
                            let arrivals = (byStop[stop.stopId] ?? [])
                                .filter { $0.routeId == stop.routeId }
                                .sorted {
                                    ($0.effectiveArrival ?? .distantFuture)
                                        < ($1.effectiveArrival ?? .distantFuture)
                                }
                            return makeDisplay(stop: stop, soonest: arrivals.first, now: now)
                        }
                        await send(._arrivalsLoaded(display, inWindow: true, error: nil))
                    } catch {
                        await send(._arrivalsLoaded([], inWindow: true, error: "\(error)"))
                    }
                }

            case let ._arrivalsLoaded(arrivals, inWindow, error):
                state.arrivals = arrivals
                state.inWindow = inWindow
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
        isLate: isLate,
        isLive: arrival.isLive
    )
}
