import ComposableArchitecture
import Dao
import SQLiteData
import SwiftUI

@Reducer
public struct TrackeeReminderTimesFeature: Sendable {
    @Dependency(\.defaultDatabase) var defaultDatabase
    
    @ObservableState
    public struct State: Equatable {
        @FetchAll
        var reminderTimes: [ReminderTimes]
        
        public init(trackeeId: Trackees.ID) {
            self._reminderTimes = FetchAll(
                ReminderTimes.all.where { $0.trackeeId.eq(trackeeId) },
                animation: .default
            )
        }
    }
    
    public enum Action {
        case trackeeReminderTime(TrackeeReminderTimeFeature.Action)
    }
    
    public init() { }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .trackeeReminderTime:
                return .none
                //case .binding:
                //return .none
//            case .onAppear:
//                return .run{ [trackeeId = state.trackeeId, rT = state.$reminderTimes] send in
//                    await withErrorReporting {
//                        try await rT.load(
//                            ReminderTimes.where{
//                                $0.trackeeId.eq(trackeeId)
//                            }
//                        );
//                    }
//                }
//            case .addNewReminderTime:
//                withErrorReporting {
//                    try self.defaultDatabase.write { db in
//                        var newReminder = ReminderTimes(trackeeId: state.trackeeId, weekDay: 1, hour: 1, minute: 1)
//                        try ReminderTimes.insert(newReminder).execute(db)
//                    }
//                }
//                return .none
            }
        }
    }
}

public struct TrackeeReminderTimesView: View {
    @Bindable var store: StoreOf<TrackeeReminderTimesFeature>
    
    public init(store: StoreOf<TrackeeReminderTimesFeature>) {
        self.store = store
    }
    
    public var body: some View {
        List {
            ForEach(store.reminderTimes, id: \.id){ reminderTime in
                TrackeeReminderTimeView(store: store.scope(state: $reminderTime, action: \.trackeeReminderTime))
            }
            Button("Add New Reminder"){
                store.send(.addNewReminderTime)
            }
        }
    }
}
