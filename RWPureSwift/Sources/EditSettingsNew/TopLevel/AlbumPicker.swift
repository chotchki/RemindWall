import AppTypes
import ComposableArchitecture
import Dependencies
import Photos
import PhotoKitAsync
import SwiftUI

@Reducer
public struct AlbumPickerFeature {
    @Dependency(\.photoKitAlbums) var photoKitAlbums
    
    @ObservableState
    public struct State: Equatable {
        @Shared(.appStorage(ALBUM_SETTING_KEY)) var selectedAlbum: AlbumLocalId?
        var photoStatus: PHAuthorizationStatus = .notDetermined
        var availibleAlbums: PHFetchResultCollection<PHAssetCollection>?
        
        public init(){}
    }
    
    public enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onAppear
        case tapOpenSettings
        case tapAuthorizeAccess
        case loadListComplete(PHFetchResultCollection<PHAssetCollection>?)
    }
    
    public init(){}
    
    public var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none
            case .onAppear:
                state.photoStatus = photoKitAlbums.libraryAccess();
                return loadList(state: &state)
            case .tapOpenSettings:
                photoKitAlbums.openPhotoSettings()
                return loadList(state: &state)
            case .tapAuthorizeAccess:
                return .run{ [photoKitAlbums] send in
                    await photoKitAlbums.requestAuthorization()
                }
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
    @Bindable var store: StoreOf<AlbumPickerFeature>
    
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
                Picker("Albums", selection: $store.selectedAlbum){
                    ForEach(store.availibleAlbums!, id: \.localIdentifier) { album in
                        Text(album.localizedTitle ?? "Unknown Album").tag(AlbumLocalId(album.localIdentifier))
                    }
                }.pickerStyle(.navigationLink)
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


