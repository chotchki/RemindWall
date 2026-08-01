import AppTypes
import ComposableArchitecture
import Dao
import Dependencies
import EditSettingsNew_BusSettings
import Foundation
import HomeKitAsync
import SwiftUI

@Reducer
public struct BatterySettingsFeature: Sendable {
    @Dependency(\.homeKitAsync) var homeKitAsync

    @ObservableState
    public struct State: Equatable {
        @Shared(.syncedSetting(BATTERY_ALERTS_ENABLED_SETTING_KEY)) public var enabled: Bool = false
        @Shared(.syncedSetting(BATTERY_THRESHOLD_SETTING_KEY)) public var thresholdPercent: Int = 20
        /// nil = chips show whenever a battery is low; a window limits WHEN.
        @Shared(.syncedSetting(BATTERY_WINDOW_SETTING_KEY)) public var window: AlertWindow?
        /// Accessories that lie about their batteries (H1.7).
        @Shared(.syncedSetting(BATTERY_IGNORED_SETTING_KEY)) public var ignored: BatteryIgnoreList = .empty

        /// Everything the house reports, alertable or not - HomeKit battery
        /// reporting is vendor-soup, so the browser shows the raw truth.
        public var discovered: [BatteryStatus] = []
        public var isLoadingBatteries: Bool = false
        public var isDetailPresented: Bool = false

        /// The one line the settings form shows; everything else lives in
        /// the sheet (H1.8 - a 15-accessory browser was eating the form).
        public var summary: String {
            var parts = ["Below \(thresholdPercent)%", window?.summary ?? "always"]
            let ignoredCount = ignored.names.count
            if ignoredCount > 0 {
                parts.append("\(ignoredCount) ignored")
            }
            return parts.joined(separator: " · ")
        }

        public init() {}
    }

    public enum Action: Equatable {
        case onAppear
        case setDetailPresented(Bool)
        case thresholdChanged(Int)
        case windowedToggled(Bool)
        case setWindowStart(hour: Int, minute: Int)
        case setWindowEnd(hour: Int, minute: Int)
        case toggleWeekday(DaysOfWeek)
        case refreshBatteries
        case ignoreToggled(accessoryName: String)
        case _batteriesLoaded([BatteryStatus])
    }

    enum CancelID { case fetch }

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .send(.refreshBatteries)

            case let .setDetailPresented(isPresented):
                state.isDetailPresented = isPresented
                return .none

            case let .thresholdChanged(percent):
                state.$thresholdPercent.withLock { $0 = min(max(percent, 5), 50) }
                return .none

            case let .windowedToggled(isOn):
                state.$window.withLock { $0 = isOn ? .default : nil }
                return .none

            case let .setWindowStart(hour, minute):
                let current = state.window ?? .default
                state.$window.withLock { $0 = current.withStart(hour: hour, minute: minute) }
                return .none

            case let .setWindowEnd(hour, minute):
                let current = state.window ?? .default
                state.$window.withLock { $0 = current.withEnd(hour: hour, minute: minute) }
                return .none

            case let .toggleWeekday(day):
                let current = state.window ?? .default
                var days = current.weekdays
                if days.contains(day) { days.remove(day) } else { days.insert(day) }
                state.$window.withLock { $0 = current.withWeekdays(days) }
                return .none

            case let .ignoreToggled(accessoryName):
                state.$ignored.withLock { $0 = $0.toggling(accessoryName) }
                return .none

            case .refreshBatteries:
                state.isLoadingBatteries = true
                return .run { [homeKitAsync] send in
                    await send(._batteriesLoaded(homeKitAsync.batteryStatuses()))
                }
                .cancellable(id: CancelID.fetch, cancelInFlight: true)

            case let ._batteriesLoaded(statuses):
                state.isLoadingBatteries = false
                state.discovered = statuses.sorted {
                    if $0.levelPercent != $1.levelPercent {
                        return ($0.levelPercent ?? 0) < ($1.levelPercent ?? 0)
                    }
                    return $0.accessoryName < $1.accessoryName
                }
                return .none
            }
        }
    }
}

public struct BatterySettingsView: View {
    @Bindable var store: StoreOf<BatterySettingsFeature>

    public init(store: StoreOf<BatterySettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        // One row in the form; the details sheet holds everything else.
        Button {
            store.send(.setDetailPresented(true))
        } label: {
            HStack {
                Text(store.summary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: Binding(
            get: { store.isDetailPresented },
            set: { store.send(.setDetailPresented($0)) }
        )) {
            detailSheet
        }
    }

    private var detailSheet: some View {
        NavigationStack {
            Form {
                Section("Alert rule") {
                    Stepper(
                        "Alert below \(store.thresholdPercent)% (or when the accessory flags itself low)",
                        value: Binding(
                            get: { store.thresholdPercent },
                            set: { store.send(.thresholdChanged($0)) }
                        ),
                        in: 5...50,
                        step: 5
                    )
                }
                Section("When chips show") {
                    Toggle("Only during a window", isOn: Binding(
                        get: { store.window != nil },
                        set: { store.send(.windowedToggled($0)) }
                    ))
                    if let window = store.window {
                        AlertWindowEditorView(
                            window: window,
                            onSetStart: { hour, minute in store.send(.setWindowStart(hour: hour, minute: minute)) },
                            onSetEnd: { hour, minute in store.send(.setWindowEnd(hour: hour, minute: minute)) },
                            onToggleWeekday: { day in store.send(.toggleWeekday(day)) }
                        )
                    }
                }
                Section {
                    batteriesFound
                }
            }
            .navigationTitle("Battery Alerts")
            .toolbar {
                ToolbarItem {
                    Button("Done") { store.send(.setDetailPresented(false)) }
                }
            }
            .onAppear { store.send(.onAppear) }
        }
    }

    @ViewBuilder
    private var batteriesFound: some View {
        HStack {
            Text("Batteries found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                store.send(.refreshBatteries)
            } label: {
                if store.isLoadingBatteries {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(store.isLoadingBatteries)
            .accessibilityLabel("Refresh batteries")
        }

        if store.discovered.isEmpty, !store.isLoadingBatteries {
            Text("None found yet — is HomeKit access granted on this device?")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        ForEach(store.discovered) { status in
            let isIgnored = store.ignored.contains(status.accessoryName)
            HStack {
                VStack(alignment: .leading) {
                    Text(status.accessoryName)
                    Text(isIgnored ? "ignored" : (status.roomName ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if status.isLow, !isIgnored {
                    Text("LOW")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                Text(status.levelPercent.map { "\($0)%" } ?? "?")
                    .monospacedDigit()
                    .foregroundStyle(
                        !isIgnored && status.isAlertable(belowPercent: store.thresholdPercent)
                            ? .red : .secondary
                    )
                Button {
                    store.send(.ignoreToggled(accessoryName: status.accessoryName))
                } label: {
                    Image(systemName: isIgnored ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isIgnored ? "Stop ignoring \(status.accessoryName)" : "Ignore \(status.accessoryName)")
            }
            .opacity(isIgnored ? 0.45 : 1.0)
        }
    }
}
