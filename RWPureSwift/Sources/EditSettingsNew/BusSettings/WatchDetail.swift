import AppTypes
import ComposableArchitecture
import Dao
import Dependencies
import Foundation
import SwiftUI

@Reducer
public struct WatchDetailFeature: Sendable {
    @Dependency(\.defaultDatabase) var defaultDatabase
    @Dependency(\.dismiss) var dismiss

    @ObservableState
    public struct State: Equatable {
        public var watch: Watch

        public init(watch: Watch) {
            self.watch = watch
        }
    }

    public enum Action: Equatable {
        case enabledToggled(Bool)
        case setWindowStart(hour: Int, minute: Int)
        case setWindowEnd(hour: Int, minute: Int)
        case toggleWeekday(DaysOfWeek)
        case normalMinutesChanged(Int)
        case removeTapped
        case doneTapped
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable {
            case watchChanged
            case removeRequested(Watch.ID)
        }
    }

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .enabledToggled(isOn):
                switch state.watch {
                case var .bus(stop):
                    stop.enabled = isOn
                    state.watch = .bus(stop)
                case var .drive(route):
                    route.enabled = isOn
                    state.watch = .drive(route)
                }
                return persist(state.watch)

            case let .setWindowStart(hour, minute):
                return updateWindow(&state) { $0.withStart(hour: hour, minute: minute) }

            case let .setWindowEnd(hour, minute):
                return updateWindow(&state) { $0.withEnd(hour: hour, minute: minute) }

            case let .toggleWeekday(day):
                return updateWindow(&state) { current in
                    var days = current.weekdays
                    if days.contains(day) { days.remove(day) } else { days.insert(day) }
                    return current.withWeekdays(days)
                }

            case let .normalMinutesChanged(minutes):
                guard case var .drive(route) = state.watch else { return .none }
                route.normalMinutes = min(max(minutes, 1), 240)
                state.watch = .drive(route)
                return persist(state.watch)

            case .removeTapped:
                return .send(.delegate(.removeRequested(state.watch.id)))

            case .doneTapped:
                return .run { _ in await dismiss() }

            case .delegate:
                return .none
            }
        }
    }

    private func updateWindow(
        _ state: inout State,
        _ transform: (AlertWindow) -> AlertWindow
    ) -> Effect<Action> {
        let newWindow = transform(state.watch.window ?? .default)
        switch state.watch {
        case var .bus(stop):
            stop.window = newWindow
            state.watch = .bus(stop)
        case var .drive(route):
            route.window = newWindow
            state.watch = .drive(route)
        }
        return persist(state.watch)
    }

    /// The detail owns its row's writes; the parent reloads on watchChanged
    /// (sent AFTER the commit so the reload never reads stale).
    private func persist(_ watch: Watch) -> Effect<Action> {
        .run { send in
            await withErrorReporting {
                try await defaultDatabase.write { db in
                    switch watch {
                    case let .bus(stop):
                        try MonitoredStop.find(stop.id)
                            .update {
                                $0.enabled = stop.enabled
                                $0.window = stop.window
                            }
                            .execute(db)
                    case let .drive(route):
                        try MonitoredRoute.find(route.id)
                            .update {
                                $0.enabled = route.enabled
                                $0.window = route.window
                                $0.normalMinutes = route.normalMinutes
                            }
                            .execute(db)
                    }
                }
                await send(.delegate(.watchChanged))
            }
        }
    }
}

public struct WatchDetailView: View {
    @Bindable var store: StoreOf<WatchDetailFeature>

    public init(store: StoreOf<WatchDetailFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Watch") {
                    Toggle("Enabled", isOn: Binding(
                        get: { store.watch.enabled },
                        set: { store.send(.enabledToggled($0)) }
                    ))
                    LabeledContent("What") { Text(store.watch.label) }
                    LabeledContent("Where") { Text(store.watch.whereText) }
                    if case let .drive(route) = store.watch {
                        Stepper(
                            "Normal drive: \(route.normalMinutes) min",
                            value: Binding(
                                get: { route.normalMinutes },
                                set: { store.send(.normalMinutesChanged($0)) }
                            ),
                            in: 1...240,
                            step: 1
                        )
                    }
                }
                Section("When it matters") {
                    AlertWindowEditorView(
                        window: store.watch.window ?? .default,
                        onSetStart: { hour, minute in store.send(.setWindowStart(hour: hour, minute: minute)) },
                        onSetEnd: { hour, minute in store.send(.setWindowEnd(hour: hour, minute: minute)) },
                        onToggleWeekday: { day in store.send(.toggleWeekday(day)) }
                    )
                }
                Section {
                    Button("Remove this alert", role: .destructive) {
                        store.send(.removeTapped)
                    }
                }
            }
            .navigationTitle(store.watch.label)
            .toolbar {
                ToolbarItem {
                    Button("Done") { store.send(.doneTapped) }
                }
            }
        }
    }
}
