import AppTypes
import ComposableArchitecture
import Dao
import Dependencies
import Photos
import PhotoKitAsync
import SwiftUI

@Reducer
public struct AlbumPickerFeature {
    @Dependency(\.photoKitAlbums) var photoKitAlbums

    @ObservableState
    public struct State: Equatable {
        @Shared(.appStorage(ALBUM_SETTING_KEY)) public var selectedAlbum: AlbumLocalId?
        @Shared(.syncedSetting(ALBUM_DESCRIPTOR_SETTING_KEY)) public var albumDescriptor: AlbumDescriptor?
        var photoStatus: PHAuthorizationStatus = .notDetermined
        var availibleAlbums: PHFetchResultCollection<PHAssetCollection>?

        /// A synced pick exists but no local album matched it.
        public var needsRePick: Bool {
            selectedAlbum == nil && albumDescriptor != nil
        }

        public init(){}
    }
    
    public enum Action {
        case onAppear
        case selectAlbum(AlbumLocalId?)
        case tapOpenSettings
        case tapAuthorizeAccess
        case authorizationComplete
        case loadListComplete(PHFetchResultCollection<PHAssetCollection>?)
    }
    
    public init(){}
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.photoStatus = photoKitAlbums.libraryAccess();
                return loadList(state: &state)
            case .tapOpenSettings:
                return .run { [photoKitAlbums] send in
                    await photoKitAlbums.openPhotoSettings()
                }
            case let .selectAlbum(album):
                state.$selectedAlbum.withLock { $0 = album }
                // Sync the title so other devices can resolve the same album.
                // A failed lookup writes nothing - never clobber a synced
                // descriptor with a guess.
                if let album {
                    if let title = state.availibleAlbums?
                        .first(where: { $0.localIdentifier == album.rawValue })?
                        .localizedTitle {
                        state.$albumDescriptor.withLock { $0 = AlbumDescriptor(title) }
                    }
                } else {
                    state.$albumDescriptor.withLock { $0 = nil }
                }
                return .none
            case .tapAuthorizeAccess:
                return .run { [photoKitAlbums] send in
                    await photoKitAlbums.requestAuthorization()
                    await send(.authorizationComplete)
                }
            case .authorizationComplete:
                state.photoStatus = photoKitAlbums.libraryAccess()
                return loadList(state: &state)
            case let .loadListComplete(list):
                state.availibleAlbums = list
                return .none
            }
        }
    }
    
    func loadList(state: inout State) -> Effect<Action> {
        if state.photoStatus != .authorized && state.photoStatus != .restricted {
            state.availibleAlbums = nil
            return .none
        }
        
        return .run { [pA = self.photoKitAlbums] send in
            let availibleAlbums = await pA.availableAlbums()
            await send(.loadListComplete(availibleAlbums))
        }
    }
}

public struct AlbumPickerView: View {
    let store: StoreOf<AlbumPickerFeature>
    
    public init(store: StoreOf<AlbumPickerFeature>) {
        self.store = store
    }
    
    public var body: some View {
        HStack {
            if store.photoStatus == .denied {
                Text("In order to use this application you will need to allow full photo access in the Settings App.")
                Button("Open Settings Application"){
                    store.send(.tapOpenSettings)
                }
            } else if store.photoStatus == .restricted {
                Text("In order to use this application you will need to allow full photo access from Screen Time.")
                Button("Open Settings Application"){
                    store.send(.tapOpenSettings)
                }
            } else if store.photoStatus != .authorized {
                Button("Authorize Photo Access"){
                    store.send(.tapAuthorizeAccess)
                }
            } else if store.availibleAlbums == nil {
                ContentUnavailableView("No Albums Found", image: "photo")
            } else {
                VStack(alignment: .leading) {
                    if store.needsRePick {
                        Label(
                            "Synced album \"\(store.albumDescriptor?.rawValue ?? "")\" isn't in this device's library — pick again.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("AlbumNeedsRePick")
                    }
                    Picker("Albums", selection: Binding(
                        get: { store.selectedAlbum },
                        set: { store.send(.selectAlbum($0)) }
                    )){
                        ForEach(store.availibleAlbums!, id: \.localIdentifier) { album in
                            Text(album.localizedTitle ?? "Unknown Album").tag(AlbumLocalId(album.localIdentifier) as AlbumLocalId?)
                        }
                    }
                    #if !os(macOS)
                    .pickerStyle(.navigationLink)
                    #endif
                }
            }
        }.onAppear(perform:{
            store.send(.onAppear)
        })
    }
}

#Preview {
    let _ = prepareDependencies {
        $0.defaultDatabase = try! $0.appDatabase()
      }
    
    NavigationStack{
        Form {
            AlbumPickerView(
                store: Store(
                    initialState: AlbumPickerFeature.State()
                ) {
                    AlbumPickerFeature()
                }
            )
        }
    }
}


