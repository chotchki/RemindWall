import ComposableArchitecture
import Dao
import SwiftUI

@Reducer
public struct AddTrackeeFeature {
  @ObservableState
  public struct State: Equatable {
      var trackee: Trackee
  }
    
  public enum Action {
    case cancelButtonTapped
    case delegate(Delegate)
    case saveButtonTapped
    case setName(String)
    @CasePathable
    public enum Delegate: Equatable {
        case saveTrackee(Trackee)
    }
  }
    
  @Dependency(\.dismiss) var dismiss
  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .cancelButtonTapped:
          return .run { [d = self.dismiss] _ in await d() }
          
      case .delegate:
          return .none
        
      case .saveButtonTapped:
          return .run { [d = self.dismiss, trackee = state.trackee] send in
                await send(.delegate(.saveTrackee(trackee)))
                await d()
        }
        
      case let .setName(name):
        state.trackee.name = name
        return .none
      }
    }
  }

    public init(){}
}

struct AddTrackeeView: View {
  @Bindable var store: StoreOf<AddTrackeeFeature>


  var body: some View {
    Form {
      Section {
        TextField("Name", text: $store.trackee.name.sending(\.setName))
      }
    }
    .navigationTitle("Add Trackee")
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
        .disabled(store.trackee.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
  }
}

#Preview {
    @Previewable @State var trackee = Trackee(id: Trackee.ID(UUID()), name: "Bob")
    NavigationStack {
        AddTrackeeView(
            store: Store(
                initialState: AddTrackeeFeature.State(
                    trackee: trackee
                )
            )
            {
                AddTrackeeFeature()
            }
        )
    }
}
