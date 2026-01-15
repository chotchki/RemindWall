import ComposableArchitecture
import Dao
import SwiftUI
import TagScanner

@Reducer
public struct TrackeeReminderTimeFeature: Sendable {
    @ObservableState
    public struct State: Equatable {
        @Shared var reminderTime: ReminderTimes
        
        var timePickerState: TimePickerFeature.State
        var associatedTag: AssociateTagFeature.State
        
        public init(reminderTime: Shared<ReminderTimes>) {
            self._reminderTime = reminderTime
            
            self.timePickerState = TimePickerFeature.State(hour: reminderTime.hour, minute: reminderTime.minute)
            self.associatedTag = AssociateTagFeature.State(associatedTag: reminderTime.associatedTag)
        }
    }
    
    public enum Action: BindableAction {
        case binding(BindingAction<State>)
        case associateTag(AssociateTagFeature.Action)
        case timePicker(TimePickerFeature.Action)
    }
    
    public init() {}
    
    public var body: some Reducer<State, Action> {
        BindingReducer()
    }
}

public struct TrackeeReminderTimeView: View {
    @Bindable var store: StoreOf<TrackeeReminderTimeFeature>
    
    public init(store: StoreOf<TrackeeReminderTimeFeature>) {
        self.store = store
    }
    
    public var body: some View {
        HStack{
            VStack {
                Picker("Day of Week", selection: $store.reminderTime.weekDay){
                    Text("Sunday").tag(1)
                    Text("Monday").tag(2)
                    Text("Tuesday").tag(3)
                    Text("Wednesday").tag(4)
                    Text("Thursday").tag(5)
                    Text("Friday").tag(6)
                    Text("Saturday").tag(7)
                }
                HStack {
                    Text("Time of Day")
                    Spacer()
                    TimePickerView(store: store.scope(state: \.timePickerState, action: \.timePicker))
                }
                if let ls = store.reminderTime.lastScan {
                    Text("Last Scanned: \(ls)")
                } else {
                    Text("Never Scanned")
                }
            }
            
            AssociateTagView(store: store.scope(state: \.associatedTag, action: \.associateTag))
        }
    }
}
