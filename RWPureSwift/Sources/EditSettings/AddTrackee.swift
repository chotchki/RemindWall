import ComposableArchitecture
import Dao
import SwiftUI

@Reducer
struct AddTrackeeFeature {
  @ObservableState
  struct State: Equatable {
      var trackee: Trackees
  }
    
  enum Action {
    case cancelButtonTapped
    case saveButtonTapped
    case setName(String)
  }
    
  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .cancelButtonTapped:
        return .none
        
      case .saveButtonTapped:
        return .none
        
      case let .setName(name):
        state.trackee.name = name
        return .none
      }
    }
  }
}

struct AddTrackeeView: View {
  @Bindable var store: StoreOf<AddTrackeeFeature>


  var body: some View {
    Form {
      TextField("Name", text: $store.trackee.name.sending(\.setName))
      Button("Save") {
        store.send(.saveButtonTapped)
      }
    }
    .toolbar {
      ToolbarItem {
        Button("Cancel") {
          store.send(.cancelButtonTapped)
        }
      }
    }
  }
}

#Preview {
    @Previewable @State var trackee = Trackees(id: Trackees.ID(UUID()), name: "Bob")

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
