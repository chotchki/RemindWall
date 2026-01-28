import ComposableArchitecture
import SwiftUI
import TagTypes

@Reducer
public struct AssociateTagFeature : Sendable{
    @Dependency(\.tagReaderClient) var tagReaderClient
    
    @ObservableState
    public struct State: Equatable {
        @Shared var associatedTag: String?

        var scanning: Bool = false
        
        public init(associatedTag: Shared<String?>) {
            self._associatedTag = associatedTag
        }
      }
    
    public enum Action {
        case startScanningTapped
        case cancelScanningTapped
        case scanResult(ReaderState)
    }
    
    public init(){}
    
    enum CancelID { case scanTag }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .startScanningTapped:
                state.scanning = true
                return .run { send in
                    //TODO This really should use the slot name
                    let firstSlot = self.tagReaderClient.slotNames().first!
                    let scanResult = await self.tagReaderClient.nextTagId(firstSlot, .seconds(5))
                    await send(.scanResult(scanResult))
                }.cancellable(id: CancelID.scanTag, cancelInFlight: true)
            case .cancelScanningTapped:
                state.scanning = false
                return .cancel(id: CancelID.scanTag)
            case let .scanResult(newState):
                if case .tagPresent(let ts) = newState {
                    state.$associatedTag.withLock{
                        $0 = ts.hexa
                    }
                }
                state.scanning = false
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
      VStack{
          HStack{
              Image(systemName: "sensor.tag.radiowaves.forward")
              if let aT = store.associatedTag {
                  Text("Tag ID: \(aT)")
              } else {
                  Text("No Configured Tag")
              }
          }
          Divider()
          if store.scanning {
              Button {
                  store.send(.cancelScanningTapped)
              } label: {
                  Text("Cancel Scanning")
              }
          } else {
              Button {
                  store.send(.startScanningTapped)
              } label: {
                  Text("Start Scanning")
              }
          }
      }.padding()
          .background(.tertiary)
          .cornerRadius(15)
  }
}

#Preview("No Tag - None Found"){
    let aT = Shared(value:nil as String?);
    AssociateTagView(store: Store(initialState: AssociateTagFeature.State(associatedTag: aT)){
        AssociateTagFeature()
    })
}

#Preview("No Tag - Found Tag"){
    let aT = Shared(value:nil as String?);
    withDependencies {
        $0.tagReaderClient.nextTagId = {
            _,_ in
            try? await Task.sleep(nanoseconds: 2 * 1_000_000_000);
                return .tagPresent(TagSerial([0x0, 0x1, 0x2]))
        }
        } operation: {
            AssociateTagView(store: Store(initialState: AssociateTagFeature.State(associatedTag: aT)){
                AssociateTagFeature()
            })
        }
}
