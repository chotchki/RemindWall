import AppTypes
import ComposableArchitecture
import SwiftUI

@Reducer
public struct ScreenOffSettingFeature {
    @ObservableState
    public struct State: Equatable {
        @Shared(.appStorage(SCREEN_OFF_SETTING_KEY)) var schedule: ScreenOffSchedule?

        public init() {}
    }

    public enum Action {
        case setStartTime(hour: Int, minute: Int)
        case setEndTime(hour: Int, minute: Int)
        case setSchedule(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int)
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
    }
}

#Preview {
    NavigationStack {
        Form {
            ScreenOffSettingView(
                store: Store(
                    initialState: {
                        var state = ScreenOffSettingFeature.State()
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
