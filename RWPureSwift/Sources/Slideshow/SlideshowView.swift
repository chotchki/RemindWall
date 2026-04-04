import AppTypes
import ComposableArchitecture
import PhotosUI
import PhotoKitAsync
import SwiftUI

@Reducer
public struct SlideShowFeature: Sendable {
    static let slideUpdateDuration = Duration.seconds(10)

    private enum CancelID { case timer }

    @Dependency(\.continuousClock) var clock
    @Dependency(\.photoKitAlbums) var photoKitAlbums

    @ObservableState
    public struct State: Equatable {
        @Shared(.appStorage(ALBUM_SETTING_KEY)) var selectedAlbum: AlbumLocalId?

        var viewSize: CGSize = .zero
        var assetList: [PHAsset]?
        var assetLoader: AssetLoaderFeature.State?

        public init() {}
    }

    public enum Action {
        case viewAppeared
        case viewResized(CGSize)
        case delegate(Delegate)
        case tick
        case loadAlbum
        case loadAlbumContents([PHAsset]?)
        case assetLoader(AssetLoaderFeature.Action)

        @CasePathable
        public enum Delegate: Equatable {
            case tapReturnToSettings
        }
    }

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .viewAppeared:
                return .merge(
                    .send(.loadAlbum),
                    .run { send in
                        for await _ in self.clock.timer(interval: SlideShowFeature.slideUpdateDuration) {
                            await send(.tick)
                        }
                    }
                    .cancellable(id: CancelID.timer, cancelInFlight: true)
                )
            case let .viewResized(size):
                state.viewSize = size
                return .none
            case .delegate, .assetLoader:
                return .none
            case .tick:
                guard var assetList = state.assetList else { return .none }

                if assetList.isEmpty {
                    return .send(.loadAlbum)
                } else {
                    state.assetLoader = AssetLoaderFeature.State(
                        size: state.viewSize,
                        asset: assetList.removeFirst(), nextAsset: assetList.first
                    )
                    state.assetList = assetList
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
                        size: state.viewSize,
                        asset: assetList.removeFirst(), nextAsset: assetList.first
                    )
                    state.assetList = assetList
                }
                return .none
            }
        }.ifLet(\.assetLoader, action: \.assetLoader) {
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
        GeometryReader { reader in
            Group {
                if let al = store.scope(state: \.assetLoader, action: \.assetLoader) {
                    AssetLoaderView(store: al)
                        .id(al.asset.localIdentifier)
                } else if store.selectedAlbum == nil {
                    ContentUnavailableView {
                        Label("Slideshow Not Configured", systemImage: "photo.stack")
                    } description: {
                        Text("Select a shared album to display in settings.")
                    } actions: {
                        Button("Return to Settings") {
                            store.send(.delegate(.tapReturnToSettings))
                        }
                    }
                    .accessibilityIdentifier("SlideshowNotConfigured")
                } else {
                    ContentUnavailableView {
                        Label("Slideshow Loading", systemImage: "photo.stack")
                    } description: {
                        ProgressView()
                    } actions: {
                        Button("Return to Settings") {
                            store.send(.delegate(.tapReturnToSettings))
                        }
                    }
                    .accessibilityIdentifier("SlideshowLoading")
                }
            }
            .onChange(of: reader.size, initial: true) { _, newSize in
                store.send(.viewResized(newSize))
            }
        }.onAppear {
            store.send(.viewAppeared)
        }
    }
}

#Preview {
    let _ = prepareDependencies {
        $0.defaultDatabase = try! $0.appDatabase()
    }

    SlideshowView(
        store: Store(
            initialState: SlideShowFeature.State()
        ) {
            SlideShowFeature()
        }
    )
}
