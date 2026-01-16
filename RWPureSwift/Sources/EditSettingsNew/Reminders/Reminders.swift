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
        }
    }
    
    public enum Action {
        case onAppear
        case addReminderButtonTapped
        case deleteReminder(IndexSet)
        case destination(PresentationAction<Destination.Action>)
    }
    
    public init() {
    }
    
    public var body: some ReducerOf<Self> {
        Reduce<State, Action> { state, action in
            switch action {
            case .onAppear:
                return .run { [t = state.trackee, rt = state.$reminderTimes] send in
                    await withErrorReporting {
                        try await rt.load(ReminderTime.where{$0.trackeeId ==  t.id}.order(by: \.weekDay).order(by: \.hour).order(by: \.minute))
                    }
                }
                
            case .addReminderButtonTapped:
                state.destination = .addReminder(AddReminderFeature.State(trackee: state.trackee))
                return .none
                
            case let .deleteReminder(indexSet):
                return .run { [t = state.trackee, rt = state.$reminderTimes] send in
                    await withErrorReporting {
                        try await defaultDatabase.write { db in
                            try ReminderTime.find(indexSet.map { rt[$0].id })
                                .delete().execute(db)
                        }
                        // Refresh the list
                        try await rt.load(ReminderTime.where{$0.trackeeId ==  t.id}.order(by: \.weekDay).order(by: \.hour).order(by: \.minute))
                    }
                }
            case let .destination(.presented(.addReminder(.delegate(.saveReminder(reminderPart))))):
                let trackeeId = state.trackee.id
                
                return .run { [defaultDatabase, rt = state.$reminderTimes, reminderPart] _ in
                    await withErrorReporting {
                        try await defaultDatabase.write { db in
                            try ReminderTime.insert {
                                ReminderTime.Draft(
                                    weekDay: reminderPart.weekDay.rawValue,
                                    hour: reminderPart.hour,
                                    minute: reminderPart.minute,
                                    associatedTag: "", //TODO Add in tag scanning
                                    lastScan: nil,
                                    trackeeId: trackeeId
                                );
                            }.execute(db)
                        }
                        
                        // Refresh the list
                        try await rt.load(ReminderTime.where{$0.trackeeId ==  trackeeId}.order(by: \.weekDay).order(by: \.hour).order(by: \.minute))
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

struct RemindersView: View {
    @Bindable var store: StoreOf<RemindersFeature>
    
    public init(store: StoreOf<RemindersFeature>) {
        self.store = store
    }
        
    var body: some View {
        NavigationStack {
            List {
                if store.reminderTimes.isEmpty {
                    ContentUnavailableView(
                        "No Reminders",
                        systemImage: "bell.slash",
                        description: Text("Add a reminder to get started")
                    )
                } else {
                    ForEach(store.reminderTimes) { reminder in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(describing:reminder.weekDay))
                                    .font(.headline)
                                Text(formatTime(hour: reminder.hour, minute: reminder.minute))
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                                
                                if let tag = reminder.associatedTag {
                                    Label(tag, systemImage: "sensor.tag.radiowaves.forward")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    .onDelete { indexSet in
                        store.send(.deleteReminder(indexSet))
                    }
                }
            }
            .navigationTitle("Reminders for \(store.trackee.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.send(.addReminderButtonTapped)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                store.send(.onAppear)
            }
            .sheet(item: $store.scope(state: \.destination?.addReminder, action: \.destination.addReminder)) { store in
                AddReminderView(store: store)
            }
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
                    RemindersView(
                        store: Store(
                            initialState: RemindersFeature.State(trackee: trackee!)
                        ) {
                            RemindersFeature()
                        }
                    )
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

