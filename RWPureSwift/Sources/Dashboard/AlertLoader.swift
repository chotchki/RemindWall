import AppTypes
import ComposableArchitecture
import Dao
import Dependencies
import Foundation

@Reducer
public struct AlertLoaderFeature: Sendable {
    @Dependency(\.continuousClock) var clock
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date.now) var now
    @Dependency(\.calendar) var calendar

    static let refreshInterval = Duration.seconds(5)

    @ObservableState
    public struct State: Equatable {
        public var lateTrackeeNames: [String] = []

        public init() {}
    }

    public enum Action: Equatable {
        case startMonitoring
        case tick
        case _lateTrackeesLoaded([String])
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
                return .run { [database, now, calendar] send in
                    let lateNames = try await database.read { db in
                        let allReminders = try ReminderTime.all.fetchAll(db)
                        let lateTrackeeIds = Set(
                            allReminders
                                .filter { $0.isLate(date: now, calendar: calendar) }
                                .map { $0.trackeeId }
                        )

                        let allTrackees = try Trackee.all.fetchAll(db)
                        return allTrackees
                            .filter { lateTrackeeIds.contains($0.id) }
                            .map { $0.name }
                    }
                    await send(._lateTrackeesLoaded(lateNames))
                }

            case let ._lateTrackeesLoaded(names):
                state.lateTrackeeNames = names
                return .none
            }
        }
    }
}
