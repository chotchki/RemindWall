import AppTypes
import ComposableArchitecture
import Dao
import SQLiteData
import SwiftUI
import EditSettingsNew_Trackees

@Reducer
public struct SettingsFeature {
    @Dependency(\.defaultDatabase) var defaultDatabase
    @Dependency(\.uuid) var uuid
    
    @ObservableState
    public struct State: Equatable {
        @Shared var setting: Setting
        
        var trackeesState = TrackeesFeature.State()
        
        var albumPickerState: AlbumPickerFeature.State
        
        public init(setting: Shared<Setting>){
            self._setting = setting
            
            self.albumPickerState = AlbumPickerFeature.State(selectedAlbum: setting.selectedAlbumId)
        }
    }
    
    public enum Action {
        case trackees(TrackeesFeature.Action)
        case albumPicker(AlbumPickerFeature.Action)
        case startSlideshow
    }
    
    public init() {}
    
    public var body: some ReducerOf<Self> {
        Scope(state: \.trackeesState, action: \.trackees) {
            TrackeesFeature()
        }
        Reduce { state, action in
            switch action {
            case .trackees:
                return .none
            case .albumPicker:
                return .none
            case .startSlideshow:
                return .none
            }
        }
    }
}

struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>
    
    public init(store: StoreOf<SettingsFeature>) {
        self.store = store
    }
    
    var body: some View {
        NavigationStack {
            Form{
                Section {
                    AlbumPickerView(store: store.scope(state: \.albumPickerState, action: \.albumPicker))
                } header: {
                    Text("Select Album for Slideshow")
                }
                
                Section {
                    //Calendar Picker
                } header: {
                    Text("Select Calendar for Event Reminders")
                }
                
                Section {
                    TrackeesView(store: store.scope(state: \.trackeesState, action: \.trackees))
                } header: {
                    Text("Trackees")
                }
            }
        }.navigationTitle("Settings")
            .toolbar {
                ToolbarItem {
                    Button("Start Slideshow") {
                      store.send(.startSlideshow)
                    }
                }
            }
    }
}
