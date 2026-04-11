import AppTypes
import ComposableArchitecture
import Dao
import SQLiteData
import SwiftUI

@Reducer
public struct RemindersFeature: Sendable {
    @Dependency(\.defaultDatabase) var defaultDatabase
    @Dependency(\.uuid) var uuid
    
    @ObservableState
    public struct State: Equatable {
        let trackee: Trackee
        
        @Presents var destination: Destination.State?
        
        @FetchAll(ReminderTime.none)
        var reminderTimes: [ReminderTime]
        
        public init(trackee: Trackee) {
            self.trackee = trackee
            self._reminderTimes = FetchAll(
                ReminderTime.where { $0.trackeeId.eq(trackee.id) }
                    .order(by: \.weekDay)
                    .order(by: \.hour)
                    .order(by: \.minute)
            )
        }
    }
    
    public enum Action {
        case addReminderButtonTapped
        case deleteReminder(ReminderTime.ID)
        case destination(PresentationAction<Destination.Action>)
    }
    
    public init() {
    }
    
    public var body: some ReducerOf<Self> {
        Reduce<State, Action> { state, action in
            switch action {
            case .addReminderButtonTapped:
                state.destination = .addReminder(AddReminderFeature.State(trackee: state.trackee))
                return .none
                
            case let .deleteReminder(id):
                return .run { [t = state.trackee, rt = state.$reminderTimes] send in
                    _ = await withErrorReporting {
                        try await defaultDatabase.write { db in
                            try ReminderTime.find(id)
                                .delete().execute(db)
                        }
                        // Refresh the list
                        try await rt.load(ReminderTime.where{$0.trackeeId.eq(t.id)}.order(by: \.weekDay).order(by: \.hour).order(by: \.minute))
                    }
                }
            case let .destination(.presented(.addReminder(.delegate(.saveReminder(reminderTime))))):
                let trackeeId = state.trackee.id
                
                return .run { [defaultDatabase, rt = state.$reminderTimes, reminderTime] _ in
                    _ = await withErrorReporting {
                        try await defaultDatabase.write { db in
                            try ReminderTime.insert {
                                reminderTime
                            }.execute(db)
                        }
                        
                        // Refresh the list
                        try await rt.load(ReminderTime.where{$0.trackeeId.eq(trackeeId)}.order(by: \.weekDay).order(by: \.hour).order(by: \.minute))
                    }
                }
            case .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination) {
            Destination.body
        }
    }
}

extension RemindersFeature {
  @Reducer
  public enum Destination {
      case addReminder(AddReminderFeature)
  }
}

extension RemindersFeature.Destination.State: Equatable {}

public struct RemindersView: View {
    @Bindable var store: StoreOf<RemindersFeature>
    
    public init(store: StoreOf<RemindersFeature>) {
        self.store = store
    }
        
    @ViewBuilder
    public var body: some View {
        ForEach(store.reminderTimes) { reminder in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(describing:DaysOfWeek(rawValue: reminder.weekDay)!))
                        .font(.headline)
                    Text(formatTime(hour: reminder.hour, minute: reminder.minute))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    
                    if let tag = reminder.associatedTag {
                        Label(tag.hexa, systemImage: "sensor.tag.radiowaves.forward")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let lastScan = reminder.lastScan {
                        Label(lastScan.formatted(date: .abbreviated, time: .shortened), systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(role: .destructive) {
                    store.send(.deleteReminder(reminder.id))
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete Reminder")
            }
            .padding(.vertical, 8)
        }
        
        Color.clear
            .frame(height: 0)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .sheet(item: $store.scope(state: \.$destination, action: \.destination).addReminder) { store in
                AddReminderView(store: store)
            }
    }
    
    private func formatTime(hour: Int, minute: Int) -> String {
        let hour12 = hour % 12
        let displayHour = hour12 == 0 ? 12 : hour12
        let period = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }
}

#Preview {
    let _ = prepareDependencies {
        $0.defaultDatabase = try! $0.appDatabase();
    }
    
    struct AsyncTestView: View {
        @Dependency(\.defaultDatabase) var defaultDatabase
        
        @State var trackee: Trackee? = nil
        
        var body: some View {
            HStack{
                if trackee != nil {
                    List {
                        RemindersView(
                            store: Store(
                                initialState: RemindersFeature.State(trackee: trackee!)
                            ) {
                                RemindersFeature()
                            }
                        )
                    }
                } else {
                    EmptyView()
                }
            }.task {
                trackee = try! defaultDatabase.read { db in
                    try? Trackee.all.fetchOne(db)
                }
            }
        }
    }
    
    return AsyncTestView()
}

