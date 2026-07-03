import AppTypes
import ComposableArchitecture
import Dependencies
import Foundation
import os
import ScreenControl

private let logger = Logger(subsystem: "RemindWall", category: "ScreenOffMonitor")

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
        public var isSlideshowPlaying: Bool = false
        public var hasLateReminders: Bool = false

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
                if let saved = state.savedBrightness {
                    let brightness = saved
                    state.isDimmed = false
                    state.savedBrightness = nil
                    return .merge(
                        .cancel(id: CancelID.monitorLoop),
                        .run { [screenControl] _ in
                            try await screenControl.setBrightness(brightness)
                        } catch: { error, _ in
                            logger.warning("restore on stop failed: \(error.localizedDescription, privacy: .public)")
                        }
                    )
                }
                return .cancel(id: CancelID.monitorLoop)

            case .tick:
                let schedule = state.schedule
                let isSlideshowPlaying = state.isSlideshowPlaying
                let hasLateReminders = state.hasLateReminders
                return .run { [screenControl, now, calendar] send in
                    let shouldDim: Bool
                    if let schedule, isSlideshowPlaying, !hasLateReminders {
                        let hour = calendar.component(.hour, from: now)
                        let minute = calendar.component(.minute, from: now)
                        let currentTotalMinutes = hour * 60 + minute
                        shouldDim = schedule.isInOffWindow(currentTotalMinutes: currentTotalMinutes)
                    } else {
                        shouldDim = false
                    }
                    let currentBrightness = try await screenControl.getBrightness()
                    await send(._evaluated(shouldDim: shouldDim, currentBrightness: currentBrightness))
                } catch: { error, _ in
                    // DDC unreachable (daemon down, panel asleep): skip the tick and
                    // let the 30s loop retry. NEVER fabricate a brightness — the old
                    // `?? 1.0` here made a failed read look like a bright screen and
                    // corrupted the restore level.
                    logger.warning("tick skipped, brightness unreadable: \(error.localizedDescription, privacy: .public)")
                }

            case let ._evaluated(shouldDim, currentBrightness):
                if shouldDim && !state.isDimmed {
                    state.isDimmed = true
                    state.savedBrightness = currentBrightness
                    return .run { [screenControl] _ in
                        try await screenControl.setBrightness(0.0)
                    } catch: { error, _ in
                        logger.warning("dim failed: \(error.localizedDescription, privacy: .public)")
                    }
                } else if !shouldDim && state.isDimmed {
                    // Transition out of dim: attempt restore but keep savedBrightness
                    // so we can retry if setBrightness silently fails on iOS.
                    let saved = state.savedBrightness ?? 1.0
                    state.isDimmed = false
                    return .run { [screenControl] _ in
                        try await screenControl.setBrightness(saved)
                    } catch: { error, _ in
                        // savedBrightness stays set - the enforcement branch below
                        // retries on subsequent ticks.
                        logger.warning("restore failed, will retry: \(error.localizedDescription, privacy: .public)")
                    }
                } else if !shouldDim && !state.isDimmed, let saved = state.savedBrightness {
                    // Brightness enforcement: verify restore actually took effect.
                    // If current brightness is still near zero, re-apply.
                    if currentBrightness < 0.01 {
                        return .run { [screenControl] _ in
                            try await screenControl.setBrightness(saved)
                        } catch: { error, _ in
                            logger.warning("restore retry failed: \(error.localizedDescription, privacy: .public)")
                        }
                    } else {
                        // Brightness confirmed restored, clear saved value.
                        state.savedBrightness = nil
                    }
                }
                return .none
            }
        }
    }
}
