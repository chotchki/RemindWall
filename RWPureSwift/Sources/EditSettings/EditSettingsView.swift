import ComposableArchitecture
import Dependencies
import Dao
import PhotosUI
import PhotoKitAsync
import SQLiteData
import SwiftUI
import Utility

@Reducer
public struct EditSettingsFeature: Sendable {
    
    @Dependency(\.defaultDatabase) var db
    
    @ObservableState
    public struct State: Equatable {
        @FetchOne(Settings.where{$0.id == SETTINGS_SINGLETON})
        var settings: Settings?
        
        var albumPickerState = AlbumPickerFeature.State()
        
        public init() {}
    }
    
    public enum Action {
        case albumPicker(AlbumPickerFeature.Action)
    }
    
    public init(){}
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .albumPicker:
                return .none
            }
        }
    }
}

public struct EditSettingsView: View {
    var store: StoreOf<EditSettingsFeature>
    
    public var body: some View {
        NavigationStack {
            Form{
                Section {
                    ///AlbumPickerView(store: store.scope(state: \.albumPickerState, action: \.albumPickerState))
                } header: {
                    Text("Select Album for Slideshow")
                }
//                
//                Section {
//                    //Calendar Picker
//                } header: {
//                    Text("Select Calendar for Event Reminders")
//                }
//                
//                Section {
//                    TrackeesView()
//                } header: {
//                    Text("Trackees")
//                }
//                
//                Section {
//                    Button {
//                        
//                    } label: {
//                        Text("Start Slideshow")
//                    }
//                    
//                    #if targetEnvironment(macCatalyst)
//                    Button {
//                        exit(0)
//                    } label: {
//                        Text("Quit Application")
//                    }
//                    #endif
//                }
            }
        }
    }
}
