import AppTypes
import ComposableArchitecture
import SwiftUI
import EditSettingsNew_Trackees

@Reducer
public struct SettingsFeature {
    
    @ObservableState
    public struct State: Equatable {
        public var trackeesState = TrackeesFeature.State()
        public var albumPickerState = AlbumPickerFeature.State()
        public var calendarPickerState = CalendarPickerFeature.State()
        public var screenOffSettingState = ScreenOffSettingFeature.State()
        public var path = StackState<TrackeeDetailFeature.State>()

        public init(){}
    }
    
    public enum Action {
        case albumPicker(AlbumPickerFeature.Action)
        case calendarPicker(CalendarPickerFeature.Action)
        case delegate(Delegate)
        case screenOffSetting(ScreenOffSettingFeature.Action)
        case trackees(TrackeesFeature.Action)
        case path(StackActionOf<TrackeeDetailFeature>)
        case calendarToggled(Bool)
        case screenOffToggled(Bool)
        case slideshowToggled(Bool)
        case startSlideshow
        
        @CasePathable
        public enum Delegate: Equatable {
            case startSlideshow
        }
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
                return .send(.delegate(.startSlideshow))
            case .delegate:
                return .none
            case let .path(.element(id: id, action: .delegate(.confirmDeletion))):
                guard let detailState = state.path[id: id]
                else { return .none }
                return .send(.trackees(.deleteTrackee(detailState.trackee.id)))
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

                Section {
                    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
                    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
                    LabeledContent("Version") {
                        Text("\(version) (\(build))")
                    }
                }

                #if targetEnvironment(macCatalyst)
                Section {
                    Button("Quit Application", role: .destructive) {
                        UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
                    }
                }
                #endif
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
