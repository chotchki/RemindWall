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
    case keypadAppendCharacter(String)
    case keypadDeleteCharacter
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

      case let .keypadAppendCharacter(character):
        state.trackee.name.append(character)
        return .none

      case .keypadDeleteCharacter:
        if !state.trackee.name.isEmpty {
            state.trackee.name.removeLast()
        }
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
      #if targetEnvironment(macCatalyst)
      Section {
          TouchKeypadView(store: store)
      }
      #endif
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

#if targetEnvironment(macCatalyst)
struct TouchKeypadView: View {
    let store: StoreOf<AddTrackeeFeature>

    @State private var isUppercase = true

    private static let numberRow = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    private static let topRow = ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"]
    private static let middleRow = ["A", "S", "D", "F", "G", "H", "J", "K", "L"]
    private static let bottomRow = ["Z", "X", "C", "V", "B", "N", "M"]

    var body: some View {
        VStack(spacing: 8) {
            keyRow(Self.numberRow, applyCase: false)
            keyRow(Self.topRow)
            keyRow(Self.middleRow)
            HStack(spacing: 4) {
                Button {
                    isUppercase.toggle()
                } label: {
                    Image(systemName: isUppercase ? "shift.fill" : "shift")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)

                ForEach(Self.bottomRow, id: \.self) { key in
                    Button {
                        store.send(.keypadAppendCharacter(isUppercase ? key : key.lowercased()))
                    } label: {
                        Text(isUppercase ? key : key.lowercased())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    store.send(.keypadDeleteCharacter)
                } label: {
                    Image(systemName: "delete.backward")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
            }
            Button {
                store.send(.keypadAppendCharacter(" "))
            } label: {
                Text("Space")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    private func keyRow(_ keys: [String], applyCase: Bool = true) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                let display = applyCase ? (isUppercase ? key : key.lowercased()) : key
                Button {
                    store.send(.keypadAppendCharacter(display))
                } label: {
                    Text(display)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
#endif

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
