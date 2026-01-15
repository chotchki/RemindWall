import ComposableArchitecture
import Dao
import SwiftUI

@Reducer
public struct EditTrackeeFeature: Sendable {
    @ObservableState
    public struct State: Equatable {
        var trackee: Trackees
    }
    
    public enum Action: BindableAction {
    }
    
    public init(id: Trackees.ID) {
        
    }
    
    public var body: some Reducer<State, Action> {
        BindingReducer()
    }
    
}

struct EditTrackeeView: View {
    @Bindable var store: StoreOf<EditTrackeeFeature>
    
    public init(store: StoreOf<EditTrackeeFeature>) {
        self.store = store
    }
    
    var body: some View {
        NavigationStack{
            Form{
                Section {
                    TextField("Name", text: $trackee.name)
                } header: {
                    Text("Name")
                }
                
                Section {
                    ReminderTimeModelsView(trackeeId: trackee.id)
                } header: {
                    Text("Reminder Times")
                }
            }
        }.navigationTitle("Edit Trackee")
    }
}

#Preview {
    let container = Trackee.preview
    
    let first = try! container.mainContext.fetch(FetchDescriptor<Trackee>()).first!
    
    return NavigationStack {
        EditTrackeeView(trackee: Bindable(first))
    }.modelContainer(container)
}
