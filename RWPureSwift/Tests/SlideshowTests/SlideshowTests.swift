import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import PhotoKitAsync
import Photos
import Testing

@testable import Slideshow

private let testSize = CGSize(width: 800, height: 600)

private func makeTestAssets(_ count: Int) -> [PHAsset] {
    (0..<count).map { _ in PHAssetMock() }
}

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
    }

    @Test("viewAppeared with selected album loads assets")
    func viewAppearedWithAlbum() async {
        let clock = TestClock()
        let assets = makeTestAssets(2)

        var state = SlideShowFeature.State()
        state.$selectedAlbum.withLock { $0 = "test-album-id" }
        state.viewSize = testSize

        let store = TestStore(initialState: state) {
            SlideShowFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.photoKitAlbums.loadAlbumAssets = { _ in assets }
        }

        store.exhaustivity = .off

        await store.send(.viewAppeared)
        await store.receive(\.loadAlbum)
        await store.receive(\.loadAlbumContents) {
            $0.assetList = [assets[1]]
            $0.assetLoader = AssetLoaderFeature.State(
                size: testSize,
                asset: assets[0], nextAsset: assets[1]
            )
        }
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
        let assets = makeTestAssets(2)

        var state = SlideShowFeature.State()
        state.assetList = assets
        state.viewSize = testSize

        let store = TestStore(initialState: state) {
            SlideShowFeature()
        }

        await store.send(.tick) {
            $0.assetLoader = AssetLoaderFeature.State(
                size: testSize,
                asset: assets[0], nextAsset: assets[1]
            )
            $0.assetList = [assets[1]]
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
        let assets = makeTestAssets(2)

        var state = SlideShowFeature.State()
        state.viewSize = testSize

        let store = TestStore(initialState: state) {
            SlideShowFeature()
        }

        await store.send(.loadAlbumContents(assets)) {
            $0.assetList = [assets[1]]
            $0.assetLoader = AssetLoaderFeature.State(
                size: testSize,
                asset: assets[0], nextAsset: assets[1]
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

    // MARK: - Slideshow advancement tests

    @Test("slideshow advances through all photos then reloads album")
    func slideshowAdvancesThroughPhotos() async {
        let assets = makeTestAssets(3)

        // Start with the first photo already displayed (post-loadAlbumContents state)
        var state = SlideShowFeature.State()
        state.viewSize = testSize
        state.assetList = [assets[1], assets[2]]
        state.assetLoader = AssetLoaderFeature.State(
            size: testSize,
            asset: assets[0], nextAsset: assets[1]
        )
        state.$selectedAlbum.withLock { $0 = "test-album-id" }

        let store = TestStore(initialState: state) {
            SlideShowFeature()
        } withDependencies: {
            $0.photoKitAlbums.loadAlbumAssets = { _ in assets }
        }

        store.exhaustivity = .off

        // First tick: advance to second photo
        await store.send(.tick) {
            $0.assetList = [assets[2]]
            $0.assetLoader = AssetLoaderFeature.State(
                size: testSize,
                asset: assets[1], nextAsset: assets[2]
            )
        }

        // Second tick: advance to third (last) photo
        await store.send(.tick) {
            $0.assetList = []
            $0.assetLoader = AssetLoaderFeature.State(
                size: testSize,
                asset: assets[2], nextAsset: nil
            )
        }

        // Third tick: empty list triggers album reload
        await store.send(.tick)
        await store.receive(\.loadAlbum)
        await store.receive(\.loadAlbumContents) {
            $0.assetList = [assets[1], assets[2]]
            $0.assetLoader = AssetLoaderFeature.State(
                size: testSize,
                asset: assets[0], nextAsset: assets[1]
            )
        }
    }

    @Test("single photo slideshow reloads album on tick")
    func singlePhotoReloadsOnTick() async {
        let assets = makeTestAssets(1)

        // Start with single photo displayed and empty remaining list
        var state = SlideShowFeature.State()
        state.viewSize = testSize
        state.assetList = []
        state.assetLoader = AssetLoaderFeature.State(
            size: testSize,
            asset: assets[0], nextAsset: nil
        )
        state.$selectedAlbum.withLock { $0 = "test-album-id" }

        let store = TestStore(initialState: state) {
            SlideShowFeature()
        } withDependencies: {
            $0.photoKitAlbums.loadAlbumAssets = { _ in assets }
        }

        store.exhaustivity = .off

        // Tick with empty list triggers reload
        await store.send(.tick)
        await store.receive(\.loadAlbum)
        await store.receive(\.loadAlbumContents) {
            $0.assetList = []
            $0.assetLoader = AssetLoaderFeature.State(
                size: testSize,
                asset: assets[0], nextAsset: nil
            )
        }
    }

    @Test("timer ticks advance slideshow via clock")
    func timerTicksAdvanceSlideshow() async {
        let clock = TestClock()
        let assets = makeTestAssets(2)

        var state = SlideShowFeature.State()
        state.$selectedAlbum.withLock { $0 = "test-album-id" }
        state.viewSize = testSize

        let store = TestStore(initialState: state) {
            SlideShowFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.photoKitAlbums.loadAlbumAssets = { _ in assets }
        }

        store.exhaustivity = .off

        await store.send(.viewAppeared)
        await store.receive(\.loadAlbum)
        await store.receive(\.loadAlbumContents) {
            $0.assetList = [assets[1]]
            $0.assetLoader = AssetLoaderFeature.State(
                size: testSize,
                asset: assets[0], nextAsset: assets[1]
            )
        }

        // Advance clock — timer should fire tick, advancing to next photo
        await clock.advance(by: SlideShowFeature.slideUpdateDuration)
        await store.receive(\.tick) {
            $0.assetList = []
            $0.assetLoader = AssetLoaderFeature.State(
                size: testSize,
                asset: assets[1], nextAsset: nil
            )
        }
    }
}
