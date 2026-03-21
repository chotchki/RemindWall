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
        var calendarPickerState = CalendarPickerFeature.State()
        var screenOffSettingState = ScreenOffSettingFeature.State()
        var path = StackState<TrackeeDetailFeature.State>()

        public init(){}
    }
    
    public enum Action {
        case albumPicker(AlbumPickerFeature.Action)
        case calendarPicker(CalendarPickerFeature.Action)
        case screenOffSetting(ScreenOffSettingFeature.Action)
        case trackees(TrackeesFeature.Action)
        case path(StackActionOf<TrackeeDetailFeature>)
        case calendarToggled(Bool)
        case screenOffToggled(Bool)
        case slideshowToggled(Bool)
        case startSlideshow
    }
    
    public init() {}
    
    public var body: some ReducerOf<Self> {
        Scope(state: \.albumPickerState, action: \.albumPicker) {
            AlbumPickerFeature()
        }

        Scope(state: \.calendarPickerState, action: \.calendarPicker) {
            CalendarPickerFeature()
        }

        Scope(state: \.screenOffSettingState, action: \.screenOffSetting) {
            ScreenOffSettingFeature()
        }

        Scope(state: \.trackeesState, action: \.trackees) {
            TrackeesFeature()
        }
        Reduce { state, action in
            switch action {
            case let .calendarToggled(isOn):
                if isOn {
                    state.calendarPickerState.$selectedCalendar.withLock { $0 = CalendarId("") }
                } else {
                    state.calendarPickerState.$selectedCalendar.withLock { $0 = nil }
                }
                return .none
            case let .screenOffToggled(isOn):
                if isOn {
                    state.screenOffSettingState.$schedule.withLock { $0 = .default }
                } else {
                    state.screenOffSettingState.$schedule.withLock { $0 = nil }
                }
                return .none
            case let .slideshowToggled(isOn):
                if isOn {
                    state.albumPickerState.$selectedAlbum.withLock { $0 = AlbumLocalId("") }
                } else {
                    state.albumPickerState.$selectedAlbum.withLock { $0 = nil }
                }
                return .none
            case .startSlideshow:
                return .none
            case let .path(.element(id: id, action: .delegate(.confirmDeletion))):
                guard let detailState = state.path[id: id]
                else { return .none }
                return .run { [trackeeId = detailState.trackee.id, dd = self.defaultDatabase] send in
                    await withErrorReporting {
                        try await dd.write { db in
                            try Trackee.find(trackeeId).delete().execute(db)
                        }
                    }
                    await send(.trackees(.reloadTrackees))
                }
            case .trackees, .albumPicker, .calendarPicker, .screenOffSetting, .path:
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
                    if store.albumPickerState.selectedAlbum != nil {
                        AlbumPickerView(store: store.scope(state: \.albumPickerState, action: \.albumPicker))
                    }
                } header: {
                    Toggle("Slideshow", isOn: Binding(
                        get: { store.albumPickerState.selectedAlbum != nil },
                        set: { store.send(.slideshowToggled($0)) }
                    ))
                }
                
                Section {
                    if store.calendarPickerState.selectedCalendar != nil {
                        CalendarPickerView(store: store.scope(state: \.calendarPickerState, action: \.calendarPicker))
                    }
                } header: {
                    Toggle("Calendar Reminders", isOn: Binding(
                        get: { store.calendarPickerState.selectedCalendar != nil },
                        set: { store.send(.calendarToggled($0)) }
                    ))
                }
                
                Section {
                    if store.screenOffSettingState.schedule != nil {
                        ScreenOffSettingView(
                            store: store.scope(state: \.screenOffSettingState, action: \.screenOffSetting)
                        )
                    }
                } header: {
                    Toggle("Screen Off", isOn: Binding(
                        get: { store.screenOffSettingState.schedule != nil },
                        set: { store.send(.screenOffToggled($0)) }
                    ))
                }

                Section {
                    TrackeesView(store: store.scope(state: \.trackeesState, action: \.trackees), isEmbedded: true)
                } header: {
                    HStack {
                        Text("Trackees")
                        Spacer()
                        Button {
                            store.send(.trackees(.addButtonTapped))
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
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
