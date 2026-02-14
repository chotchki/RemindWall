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
        @Shared var selectedAlbum: AlbumLocalId?
        var photoStatus: PHAuthorizationStatus = .notDetermined
        var availibleAlbums: PHFetchResultAssetCollection = PHFetchResultAssetCollection()
        
        public init(selectedAlbum: Shared<AlbumLocalId?>) {
            self._selectedAlbum = selectedAlbum
        }
    }
    
    public enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onAppear
        case tapOpenSettings
        case tapAuthorizeAccess
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
                return .none
            case .tapOpenSettings:
                photoKitAlbums.openPhotoSettings()
                return .none
            case .tapAuthorizeAccess:
                return .run{ [photoKitAlbums] send in
                    await photoKitAlbums.requestAuthorization()
                }
            }
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
            } else {
                Picker("Albums", selection: $store.selectedAlbum){
                    ForEach(store.availibleAlbums, id: \.localIdentifier) { album in
                        Text(album.localizedTitle ?? "Unknown Album").tag(AlbumLocalId(album.localIdentifier))
                    }
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
    
    let ali: Shared<AlbumLocalId?> = Shared(value: nil)
    
    AlbumPickerView(
    store: Store(
      initialState: AlbumPickerFeature.State(selectedAlbum: ali)
    ) {
        AlbumPickerFeature()
    }
  )
}


