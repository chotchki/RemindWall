import AppTypes
import ComposableArchitecture
import Dependencies
import Foundation
import ScreenControl

@Reducer
public struct ScreenOffMonitorFeature: Sendable {
    @Dependency(\.continuousClock) var clock
    @Dependency(\.screenControl) var screenControl
    @Dependency(\.date.now) var now
    @Dependency(\.calendar) var calendar

    static let checkInterval = Duration.seconds(30)

    @ObservableState
    public struct State: Equatable {
        @Shared(.appStorage(SCREEN_OFF_SETTING_KEY)) var schedule: ScreenOffSchedule?

        public var isDimmed: Bool = false
        public var savedBrightness: CGFloat?
        public var isMonitoring: Bool = false

        public init() {}
    }

    public enum Action: Equatable {
        case startMonitoring
        case stopMonitoring
        case tick
        case _evaluated(shouldDim: Bool, currentBrightness: CGFloat)
    }

    enum CancelID { case monitorLoop }

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .startMonitoring:
                guard !state.isMonitoring else { return .none }
                state.isMonitoring = true
                return .run { send in
                    await send(.tick)
                    for await _ in self.clock.timer(interval: Self.checkInterval) {
                        await send(.tick)
                    }
                }
                .cancellable(id: CancelID.monitorLoop, cancelInFlight: true)

            case .stopMonitoring:
                state.isMonitoring = false
                if state.isDimmed, let saved = state.savedBrightness {
                    let brightness = saved
                    state.isDimmed = false
                    state.savedBrightness = nil
                    return .merge(
                        .cancel(id: CancelID.monitorLoop),
                        .run { [screenControl] _ in
                            await screenControl.setBrightness(brightness)
                        }
                    )
                }
                return .cancel(id: CancelID.monitorLoop)

            case .tick:
                let schedule = state.schedule
                return .run { [screenControl, now, calendar] send in
                    let shouldDim: Bool
                    if let schedule {
                        let hour = calendar.component(.hour, from: now)
                        let minute = calendar.component(.minute, from: now)
                        let currentTotalMinutes = hour * 60 + minute
                        shouldDim = schedule.isInOffWindow(currentTotalMinutes: currentTotalMinutes)
                    } else {
                        shouldDim = false
                    }
                    let currentBrightness = await screenControl.getBrightness()
                    await send(._evaluated(shouldDim: shouldDim, currentBrightness: currentBrightness))
                }

            case let ._evaluated(shouldDim, currentBrightness):
                if shouldDim && !state.isDimmed {
                    state.isDimmed = true
                    state.savedBrightness = currentBrightness
                    return .run { [screenControl] _ in
                        await screenControl.setBrightness(0.0)
                    }
                } else if !shouldDim && state.isDimmed {
                    let saved = state.savedBrightness ?? 1.0
                    state.isDimmed = false
                    state.savedBrightness = nil
                    return .run { [screenControl] _ in
                        await screenControl.setBrightness(saved)
                    }
                }
                return .none
            }
        }
    }
}
