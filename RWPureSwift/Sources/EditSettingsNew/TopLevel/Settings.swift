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
        var trackeesState = TrackeesFeature.State()
        var albumPickerState = AlbumPickerFeature.State()
        var path = StackState<TrackeeDetailFeature.State>()
        
        public init(){}
    }
    
    public enum Action {
        case albumPicker(AlbumPickerFeature.Action)
        case trackees(TrackeesFeature.Action)
        case path(StackActionOf<TrackeeDetailFeature>)
        case startSlideshow
    }
    
    public init() {}
    
    public var body: some ReducerOf<Self> {
        Scope(state: \.albumPickerState, action: \.albumPicker) {
            AlbumPickerFeature()
        }
        
        Scope(state: \.trackeesState, action: \.trackees) {
            TrackeesFeature()
        }
        Reduce { state, action in
            switch action {
            case .startSlideshow:
                return .none
            case .trackees, .albumPicker, .path:
                return .none
            }
        }.forEach(\.path, action: \.path) {
            TrackeeDetailFeature()
        }
    }
}

public struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>
    
    public init(store: StoreOf<SettingsFeature>) {
        self.store = store
    }
    
    public var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
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
                    TrackeesView(store: store.scope(state: \.trackeesState, action: \.trackees), isEmbedded: true)
                } header: {
                    Text("Trackees")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem {
                    Button("Start Slideshow") {
                      store.send(.startSlideshow)
                    }
                }
            }
        } destination: { store in
            TrackeeDetailView(store: store)
        }
    }
}

#Preview {
    let _ = prepareDependencies {
        $0.defaultDatabase = try! $0.appDatabase()
      }
    
    SettingsView(
    store: Store(
      initialState: SettingsFeature.State()
    ) {
        SettingsFeature()
    }
  )
}
