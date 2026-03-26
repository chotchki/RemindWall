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
        
        var size: CGSize
        var currentAsset: AssetType = .loading
        
        public init(size: CGSize, asset: PHAsset, nextAsset: PHAsset?){
            self.size = size
            self.asset = asset
            self.nextAsset = nextAsset
        }
      }
    
    public enum Action {
        case onAppear
        case loadAsset(AssetType)
        case disappear
    }
    
    public init(){}
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { [asset = state.asset, size = state.size, nextAsset = state.nextAsset] send in
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
                return .run { [asset = state.asset, size = state.size] send in
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
        KenBurnsPanView(assetType: store.currentAsset, size: store.size)
        .onAppear(perform: {
            store.send(.onAppear)
        })
        .onDisappear(perform: {
            store.send(.disappear)
        })
    }
}
