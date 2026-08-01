import AppTypes
import ComposableArchitecture
import Dao
import Dependencies
import Foundation
import HomeKitAsync

@Reducer
public struct BatteryAlertsFeature: Sendable {
    @Dependency(\.homeKitAsync) var homeKitAsync
    @Dependency(\.continuousClock) var clock

    /// Batteries move over days - 30 minutes, not seconds.
    static let refreshInterval = Duration.seconds(60 * 30)

    @ObservableState
    public struct State: Equatable {
        @Shared(.syncedSetting(BATTERY_ALERTS_ENABLED_SETTING_KEY)) public var enabled: Bool = false
        @Shared(.syncedSetting(BATTERY_THRESHOLD_SETTING_KEY)) public var thresholdPercent: Int = 20

        public var statuses: [BatteryStatus] = []

        /// The Tier 2 chips: only alertable batteries surface, lowest level
        /// first so the most urgent chore reads first.
        public var ambientChips: [AmbientChip] {
            guard enabled else { return [] }
            return statuses
                .filter { $0.isAlertable(belowPercent: thresholdPercent) }
                .sorted {
                    if $0.levelPercent != $1.levelPercent {
                        return ($0.levelPercent ?? 0) < ($1.levelPercent ?? 0)
                    }
                    return $0.accessoryName < $1.accessoryName
                }
                .map { status in
                    AmbientChip(
                        id: "battery-\(status.id.uuidString)",
                        systemImage: "battery.25percent",
                        text: chipText(for: status)
                    )
                }
        }

        public init() {}
    }

    public enum Action: Equatable {
        case startMonitoring
        case tick
        case _statusesLoaded([BatteryStatus])
    }

    enum CancelID { case pollLoop, fetch }

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .startMonitoring:
                return .run { send in
                    await send(.tick)
                    for await _ in self.clock.timer(interval: Self.refreshInterval) {
                        await send(.tick)
                    }
                }
                .cancellable(id: CancelID.pollLoop, cancelInFlight: true)

            case .tick:
                guard state.enabled else {
                    return .send(._statusesLoaded([]))
                }
                // cancelInFlight: a HomeKit load that never resolves (the
                // H1.1 sandbox question) must not pile up a task per tick.
                return .run { [homeKitAsync] send in
                    await send(._statusesLoaded(homeKitAsync.batteryStatuses()))
                }
                .cancellable(id: CancelID.fetch, cancelInFlight: true)

            case let ._statusesLoaded(statuses):
                state.statuses = statuses
                return .none
            }
        }
    }
}

private func chipText(for status: BatteryStatus) -> String {
    if let level = status.levelPercent {
        return "\(status.accessoryName) · \(level)%"
    }
    return "\(status.accessoryName) · low"
}
