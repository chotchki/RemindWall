import AppTypes
import ComposableArchitecture
import SwiftUI
import TagTypes

@Reducer
public struct AssociateTagFeature : Sendable{
    @Dependency(\.tagReaderClient) var tagReaderClient
    
    @ObservableState
    public struct State: Equatable {
        @Shared var associatedTag: AppTypes.TagSerial?

        var scanning: Bool = false
        var errorMessage: String?
        
        public init(associatedTag: Shared<AppTypes.TagSerial?>) {
            self._associatedTag = associatedTag
        }
      }
    
    public enum Action {
        case startScanningTapped
        case cancelScanningTapped
        case scanResult(AppTypes.ReaderState)
        case dismissError
    }
    
    public init(){}
    
    enum CancelID { case scanTag }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .startScanningTapped:
                state.scanning = true
                state.errorMessage = nil
                return .run { send in
                    let scanResult = await self.tagReaderClient.nextTagId()
                    await send(.scanResult(scanResult))
                }.cancellable(id: CancelID.scanTag, cancelInFlight: true)
            case .cancelScanningTapped:
                state.scanning = false
                return .cancel(id: CancelID.scanTag)
            case let .scanResult(newState):
                state.scanning = false
                switch newState {
                case .tagPresent(let ts):
                    state.$associatedTag.withLock {
                        $0 = ts
                    }
                    state.errorMessage = nil
                case .readerError(let message):
                    state.errorMessage = message
                case .noTag:
                    state.errorMessage = "No tag detected. Please try again."
                }
                return .none
            case .dismissError:
                state.errorMessage = nil
                return .none
            }
        }
    }
}

public struct AssociateTagView: View {
  let store: StoreOf<AssociateTagFeature>
    
    public init(store: StoreOf<AssociateTagFeature>) {
        self.store = store
    }

  public var body: some View {
      VStack {
          HStack {
              Image(systemName: "sensor.tag.radiowaves.forward")
              if let aT = store.associatedTag {
                  Text("Tag ID: \(aT.hexa)")
              } else {
                  Text("No Configured Tag")
              }
          }
          
          if let errorMessage = store.errorMessage {
              HStack {
                  Image(systemName: "exclamationmark.triangle.fill")
                      .foregroundStyle(.red)
                  Text(errorMessage)
                      .foregroundStyle(.red)
                      .font(.caption)
              }
              .padding(.vertical, 4)
          }
          
          Divider()
          
          if store.scanning {
              Button {
                  store.send(.cancelScanningTapped)
              } label: {
                  HStack {
                      ProgressView()
                          .padding(.trailing, 4)
                      Text("Cancel Scanning")
                  }
              }
          } else {
              Button {
                  store.send(.startScanningTapped)
              } label: {
                  Text("Start Scanning")
              }
          }
      }
      .padding()
      .background(.tertiary)
      .cornerRadius(15)
  }
}

#Preview("No Tag - None Found"){
    let aT = Shared(value:nil as AppTypes.TagSerial?);
    withDependencies {
        $0.tagReaderClient.nextTagId = {
            try? await Task.sleep(nanoseconds: 2 * 1_000_000_000);
            return .noTag
        }
        } operation: {
            AssociateTagView(store: Store(initialState: AssociateTagFeature.State(associatedTag: aT)){
                AssociateTagFeature()
            })
        }
}

#Preview("No Tag - Found Tag"){
    let aT = Shared(value:nil as AppTypes.TagSerial?);
    
    AssociateTagView(store: Store(initialState: AssociateTagFeature.State(associatedTag: aT)){
        AssociateTagFeature()
    })
}

#Preview("Error Scan"){
    let aT = Shared(value:nil as AppTypes.TagSerial?);
    withDependencies {
        $0.tagReaderClient.nextTagId = {
            try? await Task.sleep(nanoseconds: 2 * 1_000_000_000);
            return .readerError("Oops")
        }
        } operation: {
            AssociateTagView(store: Store(initialState: AssociateTagFeature.State(associatedTag: aT)){
                AssociateTagFeature()
            })
        }
}
