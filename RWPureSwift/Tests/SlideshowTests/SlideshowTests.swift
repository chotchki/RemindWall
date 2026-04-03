import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Photos
import Testing

@testable import Slideshow

private let testSize = CGSize(width: 800, height: 600)

@MainActor
@Suite("SlideShow Feature Tests")
struct SlideshowTests {

    @Test("viewAppeared loads album and starts timer")
    func viewAppeared() async {
        let clock = TestClock()

        let store = TestStore(initialState: SlideShowFeature.State()) {
            SlideShowFeature()
        } withDependencies: {
            $0.continuousClock = clock
        }

        store.exhaustivity = .off

        await store.send(.viewAppeared)

        // viewAppeared triggers loadAlbum immediately
        await store.receive(\.loadAlbum)

        await store.finish()
    }

    @Test("viewAppeared with selected album loads assets")
    func viewAppearedWithAlbum() async {
        let clock = TestClock()
        let asset1 = PHAsset()
        let asset2 = PHAsset()

        var state = SlideShowFeature.State()
        state.$selectedAlbum.withLock { $0 = "test-album-id" }
        state.viewSize = testSize

        let store = TestStore(initialState: state) {
            SlideShowFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.photoKitAlbums.loadAlbumAssets = { _ in
                return [asset1, asset2]
            }
        }

        store.exhaustivity = .off

        await store.send(.viewAppeared)
        await store.receive(\.loadAlbum)
        await store.receive(\.loadAlbumContents) {
            $0.assetList = [asset2]
            $0.assetLoader = AssetLoaderFeature.State(
                size: testSize,
                asset: asset1, nextAsset: asset2
            )
        }

        await store.finish()
    }

    @Test("tick with empty list reloads album")
    func tickEmptyListReloads() async {
        var state = SlideShowFeature.State()
        state.assetList = []
        state.$selectedAlbum.withLock { $0 = "test-album-id" }

        let store = TestStore(initialState: state) {
            SlideShowFeature()
        } withDependencies: {
            $0.photoKitAlbums.loadAlbumAssets = { _ in nil }
        }

        store.exhaustivity = .off

        await store.send(.tick)
        await store.receive(\.loadAlbum)
    }

    @Test("tick with assets sets assetLoader")
    func tickWithAssets() async {
        let asset1 = PHAsset()
        let asset2 = PHAsset()

        var state = SlideShowFeature.State()
        state.assetList = [asset1, asset2]
        state.viewSize = testSize

        let store = TestStore(initialState: state) {
            SlideShowFeature()
        }

        await store.send(.tick) {
            $0.assetLoader = AssetLoaderFeature.State(
                size: testSize,
                asset: asset1, nextAsset: asset2
            )
            $0.assetList = [asset2]
        }
    }

    @Test("tick with nil assetList does nothing")
    func tickNilList() async {
        let store = TestStore(initialState: SlideShowFeature.State()) {
            SlideShowFeature()
        }

        await store.send(.tick)
    }

    @Test("loadAlbumContents populates state")
    func loadAlbumContents() async {
        let asset1 = PHAsset()
        let asset2 = PHAsset()

        var state = SlideShowFeature.State()
        state.viewSize = testSize

        let store = TestStore(initialState: state) {
            SlideShowFeature()
        }

        await store.send(.loadAlbumContents([asset1, asset2])) {
            $0.assetList = [asset2]
            $0.assetLoader = AssetLoaderFeature.State(
                size: testSize,
                asset: asset1, nextAsset: asset2
            )
        }
    }

    @Test("loadAlbumContents with nil does nothing")
    func loadAlbumContentsNil() async {
        let store = TestStore(initialState: SlideShowFeature.State()) {
            SlideShowFeature()
        }

        await store.send(.loadAlbumContents(nil))
    }

    @Test("loadAlbum without selected album does nothing")
    func loadAlbumNoSelection() async {
        let store = TestStore(initialState: SlideShowFeature.State()) {
            SlideShowFeature()
        }

        await store.send(.loadAlbum)
    }

    @Test("viewResized updates viewSize")
    func viewResized() async {
        let store = TestStore(initialState: SlideShowFeature.State()) {
            SlideShowFeature()
        }

        await store.send(.viewResized(testSize)) {
            $0.viewSize = testSize
        }
    }
}
