import AppTypes
import ComposableArchitecture
import Dao
import Dependencies
import Foundation
import SQLiteData

@Reducer
public struct AlertLoaderFeature: Sendable {
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date) var date
    @Dependency(\.calendar) var calendar

    static let refreshInterval = Duration.seconds(5)

    @ObservableState
    public struct State: Equatable {
        public var lateTrackeeNames: [String] = []
        public var dayOfWeek: String = ""

        @FetchAll(ReminderTime.none)
        var allReminders: [ReminderTime]

        @FetchAll(Trackee.none)
        var allTrackees: [Trackee]

        public init() {
            self._allReminders = FetchAll(ReminderTime.all)
            self._allTrackees = FetchAll(Trackee.all)
        }
    }

    public enum Action: Equatable {
        case startMonitoring
        case tick
    }

    enum CancelID { case alertLoop }

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
                .cancellable(id: CancelID.alertLoop, cancelInFlight: true)

            case .tick:
                let now = date.now
                let cal = calendar
                let lateTrackeeIds = Set(
                    state.allReminders
                        .filter { $0.isLate(date: now, calendar: cal) }
                        .map { $0.trackeeId }
                )
                state.lateTrackeeNames = state.allTrackees
                    .filter { lateTrackeeIds.contains($0.id) }
                    .map { $0.name }
                state.dayOfWeek = cal.weekdaySymbols[cal.component(.weekday, from: now) - 1]
                return .none

            }
        }
    }
}
