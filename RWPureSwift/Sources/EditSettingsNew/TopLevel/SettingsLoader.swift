import AppTypes
import ComposableArchitecture
import Dao
import SQLiteData
import SwiftUI
import EditSettingsNew_Trackees

@Reducer
public struct SettingsLoaderFeature {
    @Dependency(\.defaultDatabase) var defaultDatabase
    @Dependency(\.uuid) var uuid
    
    @ObservableState
    public struct State {
        @Shared var setting: Setting
        
        var settingsState: SettingsFeature.State?
        
        public init(){
            self._setting = Shared(value: Setting())
        }
    }
    
    public enum Action {
        case onAppear
        case settingLoaded(Setting)
        case settingsFeature(SettingsFeature.Action)
    }
    
    public init() {
    }
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run {[defaultDatabase] send in
                    _ = await withErrorReporting {
                        /// Its important to realize that this WILL return no data until settings are saved.
                        /// CloudKit sync with this library is a last writer wins model and as a result
                        /// we do not create the Settings object until first setting save, this SHOULD
                        /// stop our persistent settings loss problem we have faced but only time will tell
                        let setting = try await defaultDatabase.read { db in
                            if let setting: Setting = try? Setting.find(SETTINGS_SINGLETON).fetchOne(db){
                                return setting
                            } else {
                                return Setting()
                            }
                        }
                        await send(.settingLoaded(setting))
                    }
                }
            case let .settingLoaded(setting):
                state.$setting.withLock{
                    $0 = setting
                }
                state.settingsState = SettingsFeature.State(setting: state.$setting)
                return .none
            case .settingsFeature:
                return .none
            }
        }
        .ifLet(\.settingsState, action: \.settingsFeature) {
            SettingsFeature()
        }
    }
}

struct SettingsLoaderView: View {
    @Bindable var store: StoreOf<SettingsLoaderFeature>
    
    public init(store: StoreOf<SettingsLoaderFeature>) {
        self.store = store
    }
    
    var body: some View {
        Group {
            if let store = store.scope(state: \.settingsState, action: \.settingsFeature) {
                SettingsView(store: store)
            } else {
                ContentUnavailableView(
                    "Loading Settings",
                    systemImage: "gear.badge.xmark"
                )
            }
        }
        .onAppear {
            store.send(.onAppear)
        }
    }
}

#Preview {
    let _ = prepareDependencies {
        $0.defaultDatabase = try! $0.appDatabase()
      }
    
    SettingsLoaderView(
    store: Store(
      initialState: SettingsLoaderFeature.State()
    ) {
        SettingsLoaderFeature()
    }
  )
}
