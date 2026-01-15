import AppModel
import ComposableArchitecture
import Dao
import PhotosUI
import PhotoKitAsync
import SwiftUI

@Reducer
public struct SlideShowFeature: Sendable {
    static let slideUpdateDuration = Duration.seconds(10)
    
    @Dependency(\.continuousClock) var clock
    @Dependency(\.photoKitAlbums) var photoKitAlbums
    
    @ObservableState
    public struct State: Equatable {
        @Shared var selectedAlbum: Settings.AlbumLocalId?
        
        var assetList: [PHAsset]?
        var assetLoader: AssetLoaderFeature.State?

        public init(selectedAlbum: Shared<Settings.AlbumLocalId?>) {
            self._selectedAlbum = selectedAlbum
        }
    }
    
    public enum Action {
        case viewAppeared
        case tapReturnToSettings
        case tick
        case loadAlbum
        case loadAlbumContents([PHAsset]?)
        case assetLoader(AssetLoaderFeature.Action)
    }
    
    public init(){}
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .viewAppeared:
                return .run { send in
                    for await _ in self.clock.timer(interval: SlideShowFeature.slideUpdateDuration){
                        await send(.tick)
                    }
                }
            case .tapReturnToSettings, .assetLoader:
                return .none
            case .tick:
                guard var assetList = state.assetList else { return .none }
                
                if assetList.isEmpty {
                    return .run { send in
                        await send(.loadAlbum)
                    }
                } else {
                    state.assetLoader = AssetLoaderFeature.State(
                        asset: assetList.removeFirst(), nextAsset: assetList.first
                    )
                    
                    return .none
                }
            case .loadAlbum:
                guard let selectedAlbum = state.selectedAlbum else { return .none }
                return .run { send in
                    let albumItems = await self.photoKitAlbums.loadAlbumAssets(selectedAlbum)
                    await send(.loadAlbumContents(albumItems))
                }
            case let .loadAlbumContents(albumItems):
                state.assetList = albumItems
                
                guard var assetList = state.assetList else { return .none }
                if !assetList.isEmpty {
                    state.assetLoader = AssetLoaderFeature.State(
                        asset: assetList.removeFirst(), nextAsset: assetList.first
                    )
                }
                return .none
            }
        }.ifLet(\.assetLoader, action: \.assetLoader){
            AssetLoaderFeature()
        }
    }
}

public struct SlideshowView: View {
    @Bindable var store: StoreOf<SlideShowFeature>
    
    public init(store: StoreOf<SlideShowFeature>) {
        self.store = store
    }
    
    public var body: some View {
        Group {
            if let al = store.scope(state: \.assetLoader, action: \.assetLoader) {
                AssetLoaderView(store: al)
            } else if store.selectedAlbum == nil {
                ContentUnavailableView {
                    Label("Slideshow Not Configured", systemImage: "photo.stack")
                } description: {
                    Text("Select a shared album to display in settings,")
                } actions: {
                    Button("Return to Settings"){
                        store.send(.tapReturnToSettings)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("Slideshow Loading", systemImage: "photo.stack")
                } description: {
                    ProgressView()
                } actions: {
                    Button("Return to Settings"){
                        store.send(.tapReturnToSettings)
                    }
                }
            }
        }.onAppear(perform:{
            store.send(.viewAppeared)
        })
    }
}
