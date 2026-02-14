import AppTypes
import ComposableArchitecture
import Dependencies
import Photos
import PhotoKitAsync
import SwiftUI

@Reducer
public struct AlbumPickerFeature: Sendable {
    @Dependency(\.photoKitAlbums) var photoKitAlbums
    
    @ObservableState
    public struct State: Equatable {
        var selectedAlbum: AlbumLocalId?
        var photoStatus: PHAuthorizationStatus = .notDetermined
        var availibleAlbums: PHFetchResultAssetCollection = PHFetchResultAssetCollection()
        
        public init() {}
    }
    
    public enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onAppear
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
            }
        }
    }
}

public struct AlbumPickerView: View {
    @Bindable var store: StoreOf<AlbumPickerFeature>
    
    public init(store: StoreOf<AlbumPickerFeature>) {
        self.store = store
    }
    
    private func openPhotoSettings(){
        #if targetEnvironment(macCatalyst)
        Task{ @MainActor in
            let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos"
            await UIApplication.shared.open(URL(string: url)!)
        }
        #else
        Task{ @MainActor in
            let url = UIApplication.openSettingsURLString
            UIApplication.shared.open(URL(string: url)!)
        }
        #endif
    }
    
    public var body: some View {
        HStack {
            if store.photoStatus == .denied {
                Text("In order to use this application you will need to allow full photo access in the Settings App.")
                Button("Open Settings Application"){
                    openPhotoSettings()
                }
            } else if store.photoStatus == .restricted {
                Text("In order to use this application you will need to allow full photo access from Screen Time.")
                Button("Open Settings Application"){
                    openPhotoSettings()
                }
            } else if store.photoStatus != .authorized {
                Button("Authorize Photo Access"){
                    Task.detached(operation: {
                        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                    })
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
