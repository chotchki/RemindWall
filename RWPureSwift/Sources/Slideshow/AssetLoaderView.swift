import ComposableArchitecture
import PhotosUI
import PhotoKitAsync
import SwiftUI

@Reducer
public struct AssetLoaderFeature : Sendable{
    @Dependency(\.photoKitAssets) var photoKitAssets
    
    @ObservableState
    public struct State: Equatable {
        let asset: PHAsset
        let nextAsset: PHAsset?
        
        var size: CGSize?
        var currentAsset: AssetType = .loading
        
        public init(asset: PHAsset, nextAsset: PHAsset?){
            self.asset = asset
            self.nextAsset = nextAsset
        }
      }
    
    public enum Action {
        case resize(CGSize)
        case load
        case loadAsset(AssetType)
        case disappear
    }
    
    public init(){}
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .resize(size):
                state.size = size
                return .none
            case .load:
                guard let size = state.size else { return .none}
                return .run { [asset = state.asset, size = size, nextAsset = state.nextAsset] send in
                    let assetType = await self.photoKitAssets.loadAsset(asset, size)
                    await send(.loadAsset(assetType))
                    if let nA = nextAsset {
                        self.photoKitAssets.startCaching(nA, size)
                    }
                }
            case .loadAsset(let assetType):
                state.currentAsset = assetType
                return .none
            case .disappear:
                guard let size = state.size else { return .none}
                return .run { [asset = state.asset, size = size] send in
                    self.photoKitAssets.unloadCache(asset, size)
                }
            }
        }
    }
}

public struct AssetLoaderView: View {
    let store: StoreOf<AssetLoaderFeature>
    
    public init(store: StoreOf<AssetLoaderFeature>) {
        self.store = store
    }

    public var body: some View {
        GeometryReader { reader in
            KenBurnsPanView(assetType: store.currentAsset, size: reader.size)
                .onAppear(perform: {
                    store.send(.load)
                })
                .onChange(of: reader.size, initial: true){
                    _, newSize in
                    store.send(.resize(newSize))
                }
                .onDisappear(perform: {
                    store.send(.disappear)
                })
        }
    }
}
