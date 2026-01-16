import AppTypes
import ComposableArchitecture
import Dao
import SQLiteData
import SwiftUI

@Reducer
public struct AddReminderFeature {
    @Dependency(\.defaultDatabase)  var defaultDatabase
    @Dependency(\.uuid) var uuid
    @Dependency(\.dismiss) var dismiss
    
    @ObservableState
    public struct State: Equatable {
        let trackee: Trackee
        
        @Shared var reminderPart: ReminderPart
        var timePickerState: ReminderPartFeature.State
        
        public init(trackee: Trackee) {
            self.trackee = trackee
            self._reminderPart = Shared(value: ReminderPart())
            timePickerState = ReminderPartFeature.State(_reminderPart)
        }
    }
    
    public enum Action {
        case timePicker(ReminderPartFeature.Action)
        case saveButtonTapped
        case cancelButtonTapped
        
        case delegate(Delegate)
        @CasePathable
        public enum Delegate: Equatable {
            case saveReminder(ReminderPart)
        }
    }
    
    public init() {}
    
    public var body: some ReducerOf<Self> {
        Scope(state: \.timePickerState, action: \.timePicker) {
            ReminderPartFeature()
        }
        Reduce<State, Action> { state, action in
            switch action {
            case .timePicker:
                return .none
                
            case .saveButtonTapped:
                return .run { [dismiss, rp = state.reminderPart] send in
                    await send(.delegate(.saveReminder(rp)))
                    await dismiss()
                }
                
            case .cancelButtonTapped:
                return .run { [dismiss] send in
                    await dismiss()
                }
                
            case .delegate:
                return .none
            }
        }
    }
}

public struct AddReminderView: View {
    var store: StoreOf<AddReminderFeature>
    
    public init(store: StoreOf<AddReminderFeature>) {
        self.store = store
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Time") {
                    ReminderPartView(
                        store: store.scope(
                            state: \.timePickerState,
                            action: \.timePicker
                        )
                    )
                }
                
                Section("Tag (Optional)") {
                    
                }
            }
            .navigationTitle("Add Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        store.send(.cancelButtonTapped)
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.send(.saveButtonTapped)
                    }
                }
            }
        }
    }
}

#Preview {
    let _ = prepareDependencies {
        $0.defaultDatabase = try! $0.appDatabase()
    }
    
    let trackee = Trackee(id: Trackee.ID(UUID()), name: "Alice")
    
    AddReminderView(
        store: Store(
            initialState: AddReminderFeature.State(trackee: trackee)
        ) {
            AddReminderFeature()
        }
    )
}
