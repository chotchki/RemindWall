import ComposableArchitecture
import Dao
import SQLiteData
import SwiftUI

@Reducer
public struct TrackeesFeature: Sendable {
    @Dependency(\.defaultDatabase) var defaultDatabase
    
    @Presents var destination: Destination.State?
    var path = StackState<EditTrackeeFeature.State>()
    
    @ObservableState
    public struct State: Equatable {
        @FetchAll
        var trackees: [Trackees]
    }
    
    public enum Action {
        case onAppear
        case addButtonTapped
    }
    
    public init() {
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { [t = state.$trackees] send in
                    await withErrorReporting {
                        try await t.load(
                            Trackees.all
                        )
                    }
                }
            case .addButtonTapped:
                return .none
            }
        }
    }
}
    

struct TrackeesView: View {
    var store: StoreOf<TrackeesFeature>
    
    public init(store: StoreOf<TrackeesFeature>) {
        self.store = store
    }
    
    var body: some View {
        NavigationStack {
            List {
                if store.trackees.isEmpty {
                    Text("No trackees configured")
                } else {
                    ForEach(store.trackees){ trackee in
                        NavigationLink {
                            EmptyView()
                            //EditTrackeeView(trackee: Bindable(trackee))
                        } label: {
                            HStack {
                                Text(trackee.name)
                                Spacer()
                            }
                        }.padding()
                    }.onDelete(perform: { offsets in
                        //for offset in offsets {
                        //    let trackee = store.trackees[offset]
                        //    modelContext.delete(trackee)
                        //}
                    })
                }
            }.onAppear {
                store.send(.onAppear)
            }.navigationTitle("Trackees")
                .toolbar {
                    ToolbarItem {
                        Button {
                            store.send(.addButtonTapped)
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
        }
    }
}

#Preview {
    TrackeesView(
    store: Store(
      initialState: TrackeesFeature.State()
    ) {
        TrackeesFeature()
    }
  )
}
