import ComposableArchitecture
import Dashboard
import EditSettingsNew_TopLevel
import ScreenOffMonitor
import SwiftUI

@Reducer
public struct AppNavigationFeature {

    @ObservableState
    public struct State: Equatable {
        public var screen: Screen = .settings
        public var settingsState = SettingsFeature.State()
        public var dashboardState = DashboardFeature.State()
        public var screenOffMonitorState = ScreenOffMonitorFeature.State()

        public init() {}

        public enum Screen: Equatable {
            case settings
            case dashboard
        }
    }

    public enum Action {
        case onAppear
        case dashboard(DashboardFeature.Action)
        case screenOffMonitor(ScreenOffMonitorFeature.Action)
        case settings(SettingsFeature.Action)
        case showDashboard
        case showSettings
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.dashboardState, action: \.dashboard) {
            DashboardFeature()
        }

        Scope(state: \.screenOffMonitorState, action: \.screenOffMonitor) {
            ScreenOffMonitorFeature()
        }

        Scope(state: \.settingsState, action: \.settings) {
            SettingsFeature()
        }

        Reduce { state, action in
            switch action {
            case .onAppear:
                return .send(.screenOffMonitor(.startMonitoring))

            case .settings(.delegate(.startSlideshow)):
                state.screen = .dashboard
                return .none

            case .dashboard(.delegate(.returnToSettings)):
                state.screen = .settings
                return .none

            case .showDashboard:
                state.screen = .dashboard
                return .none

            case .showSettings:
                state.screen = .settings
                return .none

            case .settings, .screenOffMonitor, .dashboard:
                return .none
            }
        }
    }
}

public struct AppNavigationView: View {
    @Bindable var store: StoreOf<AppNavigationFeature>

    public init(store: StoreOf<AppNavigationFeature>) {
        self.store = store
    }

    public var body: some View {
        Group {
            switch store.screen {
            case .settings:
                SettingsView(store: store.scope(state: \.settingsState, action: \.settings))
            case .dashboard:
                DashboardView(store: store.scope(
                    state: \.dashboardState,
                    action: \.dashboard
                ))
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

    AppNavigationView(
        store: Store(
            initialState: AppNavigationFeature.State()
        ) {
            AppNavigationFeature()
        }
    )
}
