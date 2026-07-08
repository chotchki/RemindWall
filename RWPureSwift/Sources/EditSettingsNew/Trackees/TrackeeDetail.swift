import ComposableArchitecture
import Dao
import EditSettingsNew_Reminders
import SQLiteData
import SwiftUI

@Reducer
public struct TrackeeDetailFeature {
    @ObservableState
    public struct State: Equatable {
        @Presents var alert: AlertState<Action.Alert>?
        public var trackee: Trackee

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
        case setRemindersEnabled(Bool)
        public enum Alert: Sendable {
            case confirmDeletion
        }
        public enum Delegate {
            case confirmDeletion
        }
    }

    @Dependency(\.dismiss) var dismiss
    @Dependency(\.defaultDatabase) var defaultDatabase
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
          case let .setRemindersEnabled(enabled):
            state.trackee.remindersEnabled = enabled
            return .run { [defaultDatabase, id = state.trackee.id] _ in
                _ = await withErrorReporting {
                    try await defaultDatabase.write { db in
                        try Trackee.find(id)
                            .update { $0.remindersEnabled = enabled }
                            .execute(db)
                    }
                }
            }
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
              Toggle(
                "Reminders enabled",
                isOn: Binding(
                    get: { store.trackee.remindersEnabled },
                    set: { store.send(.setRemindersEnabled($0)) }
                )
              )
          } footer: {
              Text("When off, \(store.trackee.name) won't show up in the late-reminder alerts. Scanning their tag still works.")
          }
          Section {
              RemindersView(
                store: store.scope(state: \.reminders, action: \.remindersFeature)
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
      .toolbar {
          ToolbarItem(placement: .primaryAction) {
              Button {
                  store.send(.remindersFeature(.addReminderButtonTapped))
              } label: {
                  Image(systemName: "plus")
              }
          }
      }
      .alert($store.scope(state: \.$alert, action: \.alert))
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
