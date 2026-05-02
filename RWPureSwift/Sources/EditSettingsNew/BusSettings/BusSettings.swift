import AppTypes
import ComposableArchitecture
import Dao
import Dependencies
import Foundation
import SwiftUI
import TransitAPI

@Reducer
public struct BusSettingsFeature: Sendable {
    @Dependency(\.transitAPI) var transitAPI
    @Dependency(\.transitKeyStore) var transitKeyStore

    @ObservableState
    public struct State: Equatable {
        @Shared(.appStorage(BUS_ALERTS_ENABLED_SETTING_KEY)) public var enabled: Bool = false
        @Shared(.appStorage(BUS_WINDOW_SETTING_KEY)) public var window: BusWindow?

        public var apiKeyDraft: String = ""
        public var hasStoredApiKey: Bool = false
        public var isTestingConnection: Bool = false
        public var connectionStatus: String?
        public var monitoredStopsState = MonitoredStopsFeature.State()

        public init() {}
    }

    public enum Action {
        case onAppear
        case enabledToggled(Bool)
        case apiKeyChanged(String)
        case saveApiKey
        case testConnection
        case _connectionResult(Bool, String?)
        case setStartTime(hour: Int, minute: Int)
        case setEndTime(hour: Int, minute: Int)
        case toggleWeekday(DaysOfWeek)
        case monitoredStops(MonitoredStopsFeature.Action)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.monitoredStopsState, action: \.monitoredStops) {
            MonitoredStopsFeature()
        }

        Reduce<State, Action> { state, action in
            switch action {
            case .onAppear:
                let stored = transitKeyStore.read()
                state.apiKeyDraft = stored ?? ""
                state.hasStoredApiKey = stored?.isEmpty == false
                return .none

            case let .enabledToggled(value):
                state.$enabled.withLock { $0 = value }
                if value, state.window == nil {
                    state.$window.withLock { $0 = .default }
                }
                return .none

            case let .apiKeyChanged(value):
                state.apiKeyDraft = value
                return .none

            case .saveApiKey:
                let key = state.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                state.hasStoredApiKey = !key.isEmpty
                return .run { [transitKeyStore] _ in
                    transitKeyStore.write(key.isEmpty ? nil : key)
                }

            case .testConnection:
                let key = state.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else {
                    state.connectionStatus = "Enter an API key first"
                    return .none
                }
                state.isTestingConnection = true
                state.connectionStatus = nil
                return .run { [transitAPI] send in
                    do {
                        try await transitAPI.testConnection(apiKey: key)
                        await send(._connectionResult(true, "Connected"))
                    } catch let error as TransitAPIError {
                        await send(._connectionResult(false, message(for: error)))
                    } catch {
                        await send(._connectionResult(false, error.localizedDescription))
                    }
                }

            case let ._connectionResult(_, message):
                state.isTestingConnection = false
                state.connectionStatus = message
                return .none

            case let .setStartTime(hour, minute):
                let current = state.window ?? .default
                state.$window.withLock {
                    $0 = current.withStart(hour: hour, minute: minute)
                }
                return .none

            case let .setEndTime(hour, minute):
                let current = state.window ?? .default
                state.$window.withLock {
                    $0 = current.withEnd(hour: hour, minute: minute)
                }
                return .none

            case let .toggleWeekday(day):
                let current = state.window ?? .default
                var days = current.weekdays
                if days.contains(day) { days.remove(day) } else { days.insert(day) }
                state.$window.withLock { $0 = current.withWeekdays(days) }
                return .none

            case .monitoredStops:
                return .none
            }
        }
    }

    private func message(for error: TransitAPIError) -> String {
        switch error {
        case .unauthorized: return "API key was rejected"
        case .notFound: return "Endpoint not found"
        case .rateLimited: return "Rate limited — try again"
        case .invalidResponse: return "Unexpected response"
        case let .network(detail): return "Network error: \(detail)"
        case let .decoding(detail): return "Decoding error: \(detail)"
        }
    }
}

public struct BusSettingsView: View {
    @Bindable var store: StoreOf<BusSettingsFeature>

    public init(store: StoreOf<BusSettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        Group {
            apiKeyRow
            windowRows
            monitoredStopsRow
            testConnectionRow
        }
        .onAppear { store.send(.onAppear) }
    }

    @ViewBuilder
    private var apiKeyRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("OneBusAway API key", text: Binding(
                    get: { store.apiKeyDraft },
                    set: { store.send(.apiKeyChanged($0)) }
                ))
                #if !os(macOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
                Button("Save") { store.send(.saveApiKey) }
                    .disabled(store.apiKeyDraft.isEmpty)
            }
            Text("Need a key? Email oba_api_key@soundtransit.org")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var windowRows: some View {
        let window = store.window ?? .default
        VStack(alignment: .leading, spacing: 8) {
            DatePicker(
                "Start",
                selection: Binding(
                    get: { time(hour: window.startHour, minute: window.startMinute) },
                    set: { newDate in
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                        store.send(.setStartTime(hour: comps.hour ?? 0, minute: comps.minute ?? 0))
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            DatePicker(
                "End",
                selection: Binding(
                    get: { time(hour: window.endHour, minute: window.endMinute) },
                    set: { newDate in
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                        store.send(.setEndTime(hour: comps.hour ?? 0, minute: comps.minute ?? 0))
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            HStack {
                ForEach(DaysOfWeek.allCases, id: \.rawValue) { day in
                    Button {
                        store.send(.toggleWeekday(day))
                    } label: {
                        Text(initial(day))
                            .font(.callout)
                            .frame(width: 32, height: 32)
                            .background(window.weekdays.contains(day) ? Color.accentColor : Color.gray.opacity(0.2))
                            .foregroundStyle(window.weekdays.contains(day) ? Color.white : Color.primary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(describing: day))
                    .accessibilityValue(window.weekdays.contains(day) ? "active" : "inactive")
                }
            }
        }
    }

    @ViewBuilder
    private var monitoredStopsRow: some View {
        MonitoredStopsView(
            store: store.scope(state: \.monitoredStopsState, action: \.monitoredStops)
        )
        Button {
            store.send(.monitoredStops(.addButtonTapped))
        } label: {
            Label("Add Stop", systemImage: "plus")
        }
    }

    @ViewBuilder
    private var testConnectionRow: some View {
        Button {
            store.send(.testConnection)
        } label: {
            HStack {
                if store.isTestingConnection {
                    ProgressView()
                    Text("Testing…")
                } else {
                    Image(systemName: "network")
                    Text("Test Connection")
                }
            }
        }
        .disabled(store.isTestingConnection)

        if let status = store.connectionStatus {
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func time(hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func initial(_ day: DaysOfWeek) -> String {
        switch day {
        case .Sunday: return "S"
        case .Monday: return "M"
        case .Tuesday: return "T"
        case .Wednesday: return "W"
        case .Thursday: return "T"
        case .Friday: return "F"
        case .Saturday: return "S"
        }
    }
}
