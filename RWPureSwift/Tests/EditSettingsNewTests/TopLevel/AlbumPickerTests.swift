import AppTypes
import ComposableArchitecture
import DependenciesTestSupport
import Photos
import PhotoKitAsync
import Testing

@testable import EditSettingsNew_TopLevel

@MainActor
@Suite("AlbumPicker Feature Tests")
struct AlbumPickerTests {

    @Test("onAppear when not authorized shows authorize button state")
    func onAppearNotAuthorized() async {
        let store = TestStore(initialState: AlbumPickerFeature.State()) {
            AlbumPickerFeature()
        } withDependencies: {
            $0.photoKitAlbums.libraryAccess = { .notDetermined }
        }

        await store.send(.onAppear)
    }

    @Test("onAppear when denied shows denied state")
    func onAppearDenied() async {
        let store = TestStore(initialState: AlbumPickerFeature.State()) {
            AlbumPickerFeature()
        } withDependencies: {
            $0.photoKitAlbums.libraryAccess = { .denied }
        }

        await store.send(.onAppear) {
            $0.photoStatus = .denied
        }
    }

    @Test("onAppear when authorized loads album list")
    func onAppearAuthorized() async {
        let store = TestStore(initialState: AlbumPickerFeature.State()) {
            AlbumPickerFeature()
        } withDependencies: {
            $0.photoKitAlbums.libraryAccess = { .authorized }
            $0.photoKitAlbums.availableAlbums = { nil }
        }

        await store.send(.onAppear) {
            $0.photoStatus = .authorized
        }

        await store.receive(\.loadListComplete)
    }

    @Test("onAppear when restricted loads album list")
    func onAppearRestricted() async {
        let store = TestStore(initialState: AlbumPickerFeature.State()) {
            AlbumPickerFeature()
        } withDependencies: {
            $0.photoKitAlbums.libraryAccess = { .restricted }
            $0.photoKitAlbums.availableAlbums = { nil }
        }

        await store.send(.onAppear) {
            $0.photoStatus = .restricted
        }

        await store.receive(\.loadListComplete)
    }

    @Test("tapOpenSettings triggers openPhotoSettings")
    func tapOpenSettings() async {
        let store = TestStore(initialState: AlbumPickerFeature.State()) {
            AlbumPickerFeature()
        } withDependencies: {
            $0.photoKitAlbums.openPhotoSettings = {}
        }

        await store.send(.tapOpenSettings)
    }

    @Test("tapAuthorizeAccess requests authorization and refreshes on grant")
    func tapAuthorizeAccessGranted() async {
        let store = TestStore(initialState: AlbumPickerFeature.State()) {
            AlbumPickerFeature()
        } withDependencies: {
            $0.photoKitAlbums.requestAuthorization = {}
            $0.photoKitAlbums.libraryAccess = { .authorized }
            $0.photoKitAlbums.availableAlbums = { nil }
        }

        await store.send(.tapAuthorizeAccess)
        await store.receive(\.authorizationComplete) {
            $0.photoStatus = .authorized
        }
        await store.receive(\.loadListComplete)
    }

    @Test("tapAuthorizeAccess requests authorization and updates status on deny")
    func tapAuthorizeAccessDenied() async {
        let store = TestStore(initialState: AlbumPickerFeature.State()) {
            AlbumPickerFeature()
        } withDependencies: {
            $0.photoKitAlbums.requestAuthorization = {}
            $0.photoKitAlbums.libraryAccess = { .denied }
        }

        await store.send(.tapAuthorizeAccess)
        await store.receive(\.authorizationComplete) {
            $0.photoStatus = .denied
        }
    }

    @Test("loadListComplete sets available albums")
    func loadListComplete() async {
        var state = AlbumPickerFeature.State()
        state.photoStatus = .authorized

        let store = TestStore(initialState: state) {
            AlbumPickerFeature()
        }

        await store.send(.loadListComplete(nil))
    }

    @Test("selectAlbum updates shared state")
    func selectAlbumUpdatesState() async {
        let store = TestStore(initialState: AlbumPickerFeature.State()) {
            AlbumPickerFeature()
        }

        await store.send(.selectAlbum(AlbumLocalId("test-album-id"))) {
            $0.$selectedAlbum.withLock { $0 = AlbumLocalId("test-album-id") }
        }
    }
}
