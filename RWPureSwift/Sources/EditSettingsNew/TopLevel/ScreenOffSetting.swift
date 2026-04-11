import AppTypes
import ComposableArchitecture
import ScreenControl
import SwiftUI

@Reducer
public struct ScreenOffSettingFeature {
    @Dependency(\.continuousClock) var clock
    @Dependency(\.screenControl) var screenControl

    @ObservableState
    public struct State: Equatable {
        @Shared(.appStorage(SCREEN_OFF_SETTING_KEY)) var schedule: ScreenOffSchedule?
        public var isTesting: Bool = false

        public init() {}
    }

    public enum Action {
        case setStartTime(hour: Int, minute: Int)
        case setEndTime(hour: Int, minute: Int)
        case setSchedule(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int)
        case testScreenOff
        case _testComplete
    }

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .setStartTime(hour, minute):
                guard let s = state.schedule else { return .none }
                let clampedHour = ((hour % 24) + 24) % 24
                let clampedMinute = ((minute % 60) + 60) % 60
                state.$schedule.withLock {
                    $0 = ScreenOffSchedule(startHour: clampedHour, startMinute: clampedMinute, endHour: s.endHour, endMinute: s.endMinute)
                }
                return .none
            case let .setEndTime(hour, minute):
                guard let s = state.schedule else { return .none }
                let clampedHour = ((hour % 24) + 24) % 24
                let clampedMinute = ((minute % 60) + 60) % 60
                state.$schedule.withLock {
                    $0 = ScreenOffSchedule(startHour: s.startHour, startMinute: s.startMinute, endHour: clampedHour, endMinute: clampedMinute)
                }
                return .none
            case let .setSchedule(startHour, startMinute, endHour, endMinute):
                guard state.schedule != nil else { return .none }
                state.$schedule.withLock {
                    $0 = ScreenOffSchedule(
                        startHour: ((startHour % 24) + 24) % 24,
                        startMinute: ((startMinute % 60) + 60) % 60,
                        endHour: ((endHour % 24) + 24) % 24,
                        endMinute: ((endMinute % 60) + 60) % 60
                    )
                }
                return .none
            case .testScreenOff:
                guard !state.isTesting else { return .none }
                state.isTesting = true
                return .run { [screenControl, clock] send in
                    let savedBrightness = await screenControl.getBrightness()
                    await screenControl.setBrightness(0.0)
                    try await clock.sleep(for: .seconds(1))
                    await screenControl.setBrightness(savedBrightness)
                    await send(._testComplete)
                }
            case ._testComplete:
                state.isTesting = false
                return .none
            }
        }
    }
}

public struct ScreenOffSettingView: View {
    let store: StoreOf<ScreenOffSettingFeature>

    public init(store: StoreOf<ScreenOffSettingFeature>) {
        self.store = store
    }

    public var body: some View {
        if let schedule = store.schedule {
            VStack(spacing: 16) {
                ClockDialView(
                    startHour: schedule.startHour,
                    startMinute: schedule.startMinute,
                    endHour: schedule.endHour,
                    endMinute: schedule.endMinute,
                    onStartTimeChanged: { hour, minute in
                        store.send(.setStartTime(hour: hour, minute: minute))
                    },
                    onEndTimeChanged: { hour, minute in
                        store.send(.setEndTime(hour: hour, minute: minute))
                    },
                    onBothTimesChanged: { sh, sm, eh, em in
                        store.send(.setSchedule(startHour: sh, startMinute: sm, endHour: eh, endMinute: em))
                    }
                )
                .frame(height: 300)
                .padding(.horizontal)

                HStack(spacing: 32) {
                    timeLabel(
                        icon: "moon.fill",
                        iconColor: .indigo,
                        label: "SCREEN OFF",
                        display: schedule.startTimeDisplay
                    )
                    timeLabel(
                        icon: "sun.max.fill",
                        iconColor: .orange,
                        label: "SCREEN ON",
                        display: schedule.endTimeDisplay
                    )
                }

                Button {
                    store.send(.testScreenOff)
                } label: {
                    HStack {
                        if store.isTesting {
                            ProgressView()
                                .padding(.trailing, 4)
                            Text("Testing...")
                        } else {
                            Image(systemName: "display")
                            Text("Test Screen Off")
                        }
                    }
                }
                .disabled(store.isTesting)
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func timeLabel(
        icon: String,
        iconColor: Color,
        label: String,
        display: String
    ) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.caption)
                Text(label)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            Text(display)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(label)
    }
}

#Preview {
    NavigationStack {
        Form {
            ScreenOffSettingView(
                store: Store(
                    initialState: {
                        let state = ScreenOffSettingFeature.State()
                        state.$schedule.withLock { $0 = .default }
                        return state
                    }()
                ) {
                    ScreenOffSettingFeature()
                }
            )
        }
    }
}
