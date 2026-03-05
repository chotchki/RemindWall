import ComposableArchitecture
import Dao
import EditSettingsNew_Reminders
import SwiftUI

@Reducer
public struct TrackeeDetailFeature {
    @ObservableState
    public struct State: Equatable {
        @Presents var alert: AlertState<Action.Alert>?
        public let trackee: Trackee
        
        var reminders: RemindersFeature.State
        
        public init(trackee: Trackee) {
            self.trackee = trackee
            
            reminders = RemindersFeature.State(trackee: trackee)
        }
    }
    
    public enum Action {
        case alert(PresentationAction<Alert>)
        case delegate(Delegate)
        case deleteButtonTapped
        case remindersFeature(RemindersFeature.Action)
        public enum Alert: Sendable {
            case confirmDeletion
        }
        public enum Delegate {
            case confirmDeletion
        }
    }
    
    @Dependency(\.dismiss) var dismiss
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
          switch action {
          case .alert(.presented(.confirmDeletion)):
              return .run { [d = self.dismiss] send in
              await send(.delegate(.confirmDeletion))
              await d()
            }
          case .alert:
            return .none
          case .delegate:
            return .none
          case .deleteButtonTapped:
            state.alert = .confirmDeletion(name: state.trackee.name)
            return .none
          case .remindersFeature:
              return .none
          }
        }
        
        .ifLet(\.$alert, action: \.alert)
        
        Scope(state: \.reminders, action: \.remindersFeature) {
            RemindersFeature()
        }
    }
    
    public init(){}
}

extension AlertState where Action == TrackeeDetailFeature.Action.Alert {
  static func confirmDeletion(name: String) -> Self {
    Self {
      TextState("Delete \(name)?")
    } actions: {
      ButtonState(role: .destructive, action: .confirmDeletion) {
        TextState("Delete")
      }
    } message: {
      TextState("This trackee and all of its reminders will be permanently deleted.")
    }
  }
}

public struct TrackeeDetailView: View {
    @Bindable var store: StoreOf<TrackeeDetailFeature>
    
    public init(store: StoreOf<TrackeeDetailFeature>) {
        self.store = store
    }
    
  public var body: some View {
      Form {
          Section {
              RemindersView(
                store: store.scope(state: \.reminders, action: \.remindersFeature),
                showNavigationStack: false
              )
          } header: {
              Text("Reminders")
          }
          Section {
              Button("Delete \(store.trackee.name)", role: .destructive) {
                store.send(.deleteButtonTapped)
              }
          }
      }
      .navigationTitle(store.trackee.name)
      #if !os(macOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .alert($store.scope(state: \.alert, action: \.alert))
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
            NavigationStack {
                if trackee != nil {
                    TrackeeDetailView(
                    store: Store(
                      initialState: TrackeeDetailFeature.State(
                          trackee: trackee!
                      )
                    ) {
                        TrackeeDetailFeature()
                    })
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
