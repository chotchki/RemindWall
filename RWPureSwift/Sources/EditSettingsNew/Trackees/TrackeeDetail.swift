import ComposableArchitecture
import Dao
import SwiftUI


@Reducer
public struct TrackeeDetailFeature {
    @ObservableState
    public struct State: Equatable {
        @Presents var alert: AlertState<Action.Alert>?
        let trackee: Trackee
    }
    
    public enum Action {
        case alert(PresentationAction<Alert>)
        case delegate(Delegate)
        case deleteButtonTapped
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
            state.alert = .confirmDeletion
            return .none
          }
        }.ifLet(\.$alert, action: \.alert)
    }
    
    public init(){}
}

extension AlertState where Action == TrackeeDetailFeature.Action.Alert {
  static let confirmDeletion = Self {
    TextState("Are you sure?")
  } actions: {
    ButtonState(role: .destructive, action: .confirmDeletion) {
      TextState("Delete")
    }
  }
}

public struct TrackeeDetailView: View {
    @Bindable var store: StoreOf<TrackeeDetailFeature>
    
  public var body: some View {
      Form {
          Button("Delete", role: .destructive) {
            store.send(.deleteButtonTapped)
          }
      }
          
      .navigationTitle(Text("Trackee: \(store.trackee.name)"))
      .alert($store.scope(state: \.alert, action: \.alert))
  }
}

#Preview {
  @Previewable @State var trackee = Trackee(id: Trackee.ID(UUID()), name: "Bob")
  NavigationStack {
      TrackeeDetailView(
      store: Store(
        initialState: TrackeeDetailFeature.State(
            trackee: trackee
        )
      ) {
          TrackeeDetailFeature()
      }
    )
  }
}
