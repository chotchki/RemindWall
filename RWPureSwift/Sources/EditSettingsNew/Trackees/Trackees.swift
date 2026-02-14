import ComposableArchitecture
import Dao
import SQLiteData
import SwiftUI

@Reducer
public struct TrackeesFeature: Sendable {
    @Dependency(\.defaultDatabase) var defaultDatabase
    @Dependency(\.uuid) var uuid
    
    @ObservableState
    public struct State: Equatable {
        @Presents var destination: Destination.State?
        var path = StackState<TrackeeDetailFeature.State>()
        
        @FetchAll(Trackee.none)
        var trackees: [Trackee]
        
        public init(){}
    }
    
    public enum Action {
        case onAppear
        case addButtonTapped
        case destination(PresentationAction<Destination.Action>)
        case path(StackActionOf<TrackeeDetailFeature>)
    }
    
    public init() {
    }
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { [t = state.$trackees] send in
                    await withErrorReporting {
                        try await t.load(Trackee.all.order(by: \.name))
                    }
                }
            case .addButtonTapped:
                state.destination = .addTrackee(
                    AddTrackeeFeature.State(
                        trackee: Trackee(id: Trackee.ID(uuid()), name: "")
                    )
                )
                return .none
                
            case let .destination(.presented(.addTrackee(.delegate(.saveTrackee(trackee))))):
                return .run { [t = state.$trackees, dd = self.defaultDatabase] send in
                    await withErrorReporting {
                        try await dd.write { db in
                            try Trackee.insert{trackee}.execute(db)
                        }
                        try await t.load(Trackee.all.order(by: \.name))
                    }
                }
                
            case let .path(.element(id: id, action: .delegate(.confirmDeletion))):
              guard let detailState = state.path[id: id]
              else { return .none }
                return .run { [t = state.$trackees, id = detailState.trackee.id, dd = self.defaultDatabase] send in
                    await withErrorReporting {
                        try await dd.write { db in
                            try Trackee.find(id).delete().execute(db)
                        }
                        try await t.load(Trackee.all.order(by: \.name))
                    }
                }
                
            case .destination:
                return .none
            case .path:
                return .none
            }
        }.ifLet(\.$destination, action: \.destination) {
            Destination.body
        }.forEach(\.path, action: \.path) {
            TrackeeDetailFeature()
        }
    }
}

extension TrackeesFeature {
  @Reducer
  public enum Destination {
    case addTrackee(AddTrackeeFeature)
  }
}

extension TrackeesFeature.Destination.State: Equatable {}
    

public struct TrackeesView: View {
    @Bindable var store: StoreOf<TrackeesFeature>
    
    public init(store: StoreOf<TrackeesFeature>) {
        self.store = store
    }
    
    public var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            List {
                if store.trackees.isEmpty {
                    Text("No trackees configured")
                } else {
                    ForEach(store.trackees){ trackee in
                        NavigationLink(state: TrackeeDetailFeature.State(trackee: trackee)) {
                            HStack {
                                Text(trackee.name)
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderless)
                    }
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
        } destination: { store in
            TrackeeDetailView(store: store)
        }
        .sheet(
            item: $store.scope(state: \.destination?.addTrackee, action: \.destination.addTrackee)
          ) { addTrackeeStore in
            NavigationStack {
              AddTrackeeView(store: addTrackeeStore)
            }
          }
    }
}

#Preview {
    let _ = prepareDependencies {
        $0.defaultDatabase = try! $0.appDatabase()
      }
    
    TrackeesView(
    store: Store(
      initialState: TrackeesFeature.State()
    ) {
        TrackeesFeature()
    }
  )
}
