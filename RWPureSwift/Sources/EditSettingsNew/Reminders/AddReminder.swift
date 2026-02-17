import AppTypes
import ComposableArchitecture
import Dao
import SQLiteData
import SwiftUI
import TagScanner

@Reducer
public struct AddReminderFeature {
    @Dependency(\.defaultDatabase)  var defaultDatabase
    @Dependency(\.dismiss) var dismiss
    @Dependency(\.uuid) var uuid
    
    @ObservableState
    public struct State: Equatable {
        let trackee: Trackee
        
        @Shared var reminderPart: ReminderPart
        var timePickerState: ReminderPartFeature.State
        @Shared var tag: TagSerial?
        var associatedTagState: AssociateTagFeature.State
        
        public init(trackee: Trackee) {
            self.trackee = trackee
            self._reminderPart = Shared(value: ReminderPart())
            timePickerState = ReminderPartFeature.State(_reminderPart)
            
            self._tag = Shared(value: nil)
            self.associatedTagState = AssociateTagFeature.State(associatedTag: _tag)
        }
    }
    
    public enum Action {
        case timePicker(ReminderPartFeature.Action)
        case associateTag(AssociateTagFeature.Action)
        case saveButtonTapped
        case cancelButtonTapped
        
        case delegate(Delegate)
        @CasePathable
        public enum Delegate: Equatable {
            case saveReminder(ReminderTime.Draft)
        }
    }
    
    public init() {}
    
    public var body: some ReducerOf<Self> {
        Reduce<State, Action> { state, action in
            switch action {
            case .timePicker:
                return .none
            case .associateTag:
                return .none
                
            case .saveButtonTapped:
                return .run { [dismiss, rp = state.reminderPart, tId = state.trackee.id, at = state.tag] send in
                    let rt = ReminderTime.Draft(
                        weekDay: rp.weekDay.rawValue,
                        hour: rp.hour,
                        minute: rp.minute,
                        associatedTag: at,
                        lastScan: nil,
                        trackeeId: tId
                        )
                    await send(.delegate(.saveReminder(rt)))
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
        
        Scope(state: \.timePickerState, action: \.timePicker) {
            ReminderPartFeature()
        }
        
        Scope(state: \.associatedTagState, action: \.associateTag){
            AssociateTagFeature()
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
                
                Section("Tag") {
                    AssociateTagView(store: store.scope(state: \.associatedTagState, action: \.associateTag))
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
    let trackee = Trackee(id: Trackee.ID(UUID()), name: "Alice")
    
    AddReminderView(
        store: Store(
            initialState: AddReminderFeature.State(trackee: trackee)
        ) {
            AddReminderFeature()
        }
    )
}
