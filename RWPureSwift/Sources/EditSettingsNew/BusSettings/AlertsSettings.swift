import AppTypes
import ComposableArchitecture
import Dao
import Dependencies
import Foundation
import SQLiteData
import SwiftUI

/// One row in the unified Alerts list: a bus stop and a driving route are
/// peers (TR1.4 review decision) - each carries its own window and toggle.
public enum Watch: Equatable, Identifiable, Sendable {
    case bus(MonitoredStop)
    case drive(MonitoredRoute)

    public enum ID: Hashable, Sendable {
        case bus(MonitoredStop.ID)
        case drive(MonitoredRoute.ID)
    }

    public var id: ID {
        switch self {
        case let .bus(stop): .bus(stop.id)
        case let .drive(route): .drive(route.id)
        }
    }

    public var label: String {
        switch self {
        case let .bus(stop): stop.label
        case let .drive(route): route.label
        }
    }

    public var enabled: Bool {
        switch self {
        case let .bus(stop): stop.enabled
        case let .drive(route): route.enabled
        }
    }

    public var window: AlertWindow? {
        switch self {
        case let .bus(stop): stop.window
        case let .drive(route): route.window
        }
    }

    public var chipText: String {
        switch self {
        case let .bus(stop): stop.routeShortName
        case .drive: "🚗"
        }
    }

    public var whereText: String {
        switch self {
        case let .bus(stop): stop.stopId
        case let .drive(route): "to \(route.destinationName)"
        }
    }

    /// "MTWTF · 6:30 AM–9:00 AM" - the row self-describes when it matters.
    public var windowSummary: String {
        let window = self.window ?? .default
        let initials = DaysOfWeek.allCases
            .filter { window.weekdays.contains($0) }
            .map { String(String(describing: $0).prefix(1)) }
            .joined()
        return "\(initials) · \(window.startTimeDisplay)–\(window.endTimeDisplay)"
    }
}

@Reducer
public struct AlertsSettingsFeature: Sendable {
    @Dependency(\.defaultDatabase) var defaultDatabase

    @ObservableState
    public struct State: Equatable {
        @Presents public var destination: Destination.State?

        @FetchAll(MonitoredStop.none)
        public var stops: [MonitoredStop]
        @FetchAll(MonitoredRoute.none)
        public var routes: [MonitoredRoute]

        public var watches: [Watch] {
            stops.map(Watch.bus) + routes.map(Watch.drive)
        }

        public init() {
            self._stops = FetchAll(MonitoredStop.all.order(by: \.sortOrder))
            self._routes = FetchAll(MonitoredRoute.all.order(by: \.sortOrder))
        }
    }

    public enum Action {
        case addBusTapped
        case addDriveTapped
        case setupTapped
        case watchTapped(Watch.ID)
        case watchToggled(Watch.ID, Bool)
        case destination(PresentationAction<Destination.Action>)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce<State, Action> { state, action in
            switch action {
            case .addBusTapped:
                let nextSortOrder = (state.stops.map(\.sortOrder).max() ?? -1) + 1
                state.destination = .addBus(AddMonitoredStopFeature.State(sortOrder: nextSortOrder))
                return .none

            case .addDriveTapped:
                let nextSortOrder = (state.routes.map(\.sortOrder).max() ?? -1) + 1
                state.destination = .addDrive(AddDriveFeature.State(sortOrder: nextSortOrder))
                return .none

            case .setupTapped:
                state.destination = .setup(AlertsSetupFeature.State())
                return .none

            case let .watchTapped(id):
                guard let watch = state.watches.first(where: { $0.id == id }) else { return .none }
                state.destination = .detail(WatchDetailFeature.State(watch: watch))
                return .none

            case let .watchToggled(id, isOn):
                return .run { [stops = state.$stops, routes = state.$routes] _ in
                    await withErrorReporting {
                        try await defaultDatabase.write { db in
                            switch id {
                            case let .bus(stopId):
                                try MonitoredStop.find(stopId)
                                    .update { $0.enabled = isOn }
                                    .execute(db)
                            case let .drive(routeId):
                                try MonitoredRoute.find(routeId)
                                    .update { $0.enabled = isOn }
                                    .execute(db)
                            }
                        }
                        try await stops.load(MonitoredStop.all.order(by: \.sortOrder))
                        try await routes.load(MonitoredRoute.all.order(by: \.sortOrder))
                    }
                }

            case let .destination(.presented(.addBus(.delegate(.saveStop(draft))))):
                return .run { [stops = state.$stops] _ in
                    await withErrorReporting {
                        try await defaultDatabase.write { db in
                            try MonitoredStop.insert { draft }.execute(db)
                        }
                        try await stops.load(MonitoredStop.all.order(by: \.sortOrder))
                    }
                }

            case let .destination(.presented(.addDrive(.delegate(.saveRoute(draft))))):
                return .run { [routes = state.$routes] _ in
                    await withErrorReporting {
                        try await defaultDatabase.write { db in
                            try MonitoredRoute.insert { draft }.execute(db)
                        }
                        try await routes.load(MonitoredRoute.all.order(by: \.sortOrder))
                    }
                }

            case let .destination(.presented(.detail(.delegate(.removeRequested(id))))):
                state.destination = nil
                return .run { [stops = state.$stops, routes = state.$routes] _ in
                    await withErrorReporting {
                        try await defaultDatabase.write { db in
                            switch id {
                            case let .bus(stopId):
                                try MonitoredStop.find(stopId).delete().execute(db)
                            case let .drive(routeId):
                                try MonitoredRoute.find(routeId).delete().execute(db)
                            }
                        }
                        try await stops.load(MonitoredStop.all.order(by: \.sortOrder))
                        try await routes.load(MonitoredRoute.all.order(by: \.sortOrder))
                    }
                }

            case .destination(.presented(.detail(.delegate(.watchChanged)))):
                return .run { [stops = state.$stops, routes = state.$routes] _ in
                    await withErrorReporting {
                        try await stops.load(MonitoredStop.all.order(by: \.sortOrder))
                        try await routes.load(MonitoredRoute.all.order(by: \.sortOrder))
                    }
                }

            case .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination) {
            Destination.body
        }
    }
}

extension AlertsSettingsFeature {
    @Reducer
    public enum Destination {
        case addBus(AddMonitoredStopFeature)
        case addDrive(AddDriveFeature)
        case detail(WatchDetailFeature)
        case setup(AlertsSetupFeature)
    }
}

extension AlertsSettingsFeature.Destination.State: Equatable {}

public struct AlertsSettingsView: View {
    @Bindable var store: StoreOf<AlertsSettingsFeature>

    public init(store: StoreOf<AlertsSettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        if store.watches.isEmpty {
            Text("No alerts yet — add a bus stop or a drive.")
                .foregroundStyle(.secondary)
        }

        ForEach(store.watches) { watch in
            HStack(spacing: 10) {
                Text(watch.chipText)
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Button {
                    store.send(.watchTapped(watch.id))
                } label: {
                    VStack(alignment: .leading) {
                        Text(watch.label)
                        Text("\(watch.whereText) · \(watch.windowSummary)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { watch.enabled },
                    set: { store.send(.watchToggled(watch.id, $0)) }
                ))
                .labelsHidden()
                .accessibilityLabel("\(watch.label) enabled")
            }
            .padding(.vertical, 2)
        }

        Menu {
            Button {
                store.send(.addBusTapped)
            } label: {
                Label("Bus arrival", systemImage: "bus")
            }
            Button {
                store.send(.addDriveTapped)
            } label: {
                Label("Drive time", systemImage: "car")
            }
        } label: {
            Label("Add alert", systemImage: "plus")
        }

        Button {
            store.send(.setupTapped)
        } label: {
            HStack {
                Text("Setup")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)

        Color.clear
            .frame(height: 0)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .sheet(item: $store.scope(state: \.$destination, action: \.destination).addBus) { addStore in
                AddMonitoredStopView(store: addStore)
            }
            .sheet(item: $store.scope(state: \.$destination, action: \.destination).addDrive) { addStore in
                AddDriveView(store: addStore)
            }
            .sheet(item: $store.scope(state: \.$destination, action: \.destination).detail) { detailStore in
                WatchDetailView(store: detailStore)
            }
            .sheet(item: $store.scope(state: \.$destination, action: \.destination).setup) { setupStore in
                AlertsSetupView(store: setupStore)
            }
    }
}
