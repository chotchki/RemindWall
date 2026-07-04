import AppTypes
import ComposableArchitecture
import Dependencies
import Foundation
import os
import ScreenControl

private let logger = Logger(subsystem: "RemindWall", category: "ScreenOffMonitor")

/// Write-only display control. The kiosk's LG returns 100% corrupted DDC reads
/// (probe 2026-07-03: 26/26 garbage, values like -121...120 varying per
/// second), so state NEVER derives from reading the panel: `isDimmed` flips
/// only when a write sequence CONFIRMS, ticks are idempotent drivers that
/// re-issue the failed direction until it lands, and the restore level is a
/// known value — the level saved at dim time where reads work (iOS), a fixed
/// full-bright fallback where they don't (the Mac).
@Reducer
public struct ScreenOffMonitorFeature: Sendable {
    @Dependency(\.continuousClock) var clock
    @Dependency(\.screenControl) var screenControl
    @Dependency(\.date.now) var now
    @Dependency(\.calendar) var calendar

    static let checkInterval = Duration.seconds(30)
    /// Restore target when no brightness could be saved at dim time.
    /// A kiosk wants full bright; make this a setting if that ever changes.
    static let fallbackRestoreLevel: CGFloat = 1.0

    @ObservableState
    public struct State: Equatable {
        @Shared(.appStorage(SCREEN_OFF_SETTING_KEY)) var schedule: ScreenOffSchedule?

        /// Confirmed-dimmed: set only after the dim writes succeeded.
        public var isDimmed: Bool = false
        /// Brightness read at dim time, when readable (iOS). nil on the Mac —
        /// its DDC reads are garbage and must never become a restore target.
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
        case _dim
        case _restore
        case _dimConfirmed(savedBrightness: CGFloat?)
        case _restoreConfirmed
    }

    enum CancelID { case monitorLoop, work }

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
                let wasDimmed = state.isDimmed
                let restoreLevel = state.savedBrightness ?? Self.fallbackRestoreLevel
                state.isDimmed = false
                state.savedBrightness = nil
                return .merge(
                    .cancel(id: CancelID.monitorLoop),
                    .cancel(id: CancelID.work),
                    wasDimmed
                        ? .run { [screenControl] _ in
                            // Ceding control: best effort, nothing retries after this.
                            try? await screenControl.setDisplayPower(true)
                            try await screenControl.setBrightness(restoreLevel)
                        } catch: { error, _ in
                            logger.warning("restore on stop failed: \(error.localizedDescription, privacy: .public)")
                        }
                        : .none
                )

            case .tick:
                // Pure decision - no hardware reads. The tick just re-issues
                // whichever direction the confirmed state disagrees with.
                let shouldDim: Bool
                if let schedule = state.schedule, state.isSlideshowPlaying, !state.hasLateReminders {
                    let hour = calendar.component(.hour, from: now)
                    let minute = calendar.component(.minute, from: now)
                    shouldDim = schedule.isInOffWindow(currentTotalMinutes: hour * 60 + minute)
                } else {
                    shouldDim = false
                }

                if shouldDim && !state.isDimmed {
                    return .send(._dim)
                }
                if !shouldDim && state.isDimmed {
                    return .send(._restore)
                }
                return .none

            case ._dim:
                return .run { [screenControl] send in
                    // Save the current level where reads work (iOS). On the Mac
                    // this throws (corrupted reads are rejected downstream) and
                    // nil selects the fallback at restore time - a garbage read
                    // must never become the restore target.
                    let saved = try? await screenControl.getBrightness()
                    // Brightness first (an awake-panel op), then true power-off.
                    try await screenControl.setBrightness(0.0)
                    try await screenControl.setDisplayPower(false)
                    await send(._dimConfirmed(savedBrightness: saved))
                } catch: { error, _ in
                    // Not confirmed - the next tick re-issues ._dim.
                    logger.warning("dim failed, will retry next tick: \(error.localizedDescription, privacy: .public)")
                }
                .cancellable(id: CancelID.work, cancelInFlight: true)

            case let ._dimConfirmed(savedBrightness):
                state.isDimmed = true
                state.savedBrightness = savedBrightness
                return .none

            case ._restore:
                let restoreLevel = state.savedBrightness ?? Self.fallbackRestoreLevel
                return .run { [screenControl] send in
                    // Wake first, then set - the reverse of the dim order.
                    try await screenControl.setDisplayPower(true)
                    try await screenControl.setBrightness(restoreLevel)
                    await send(._restoreConfirmed)
                } catch: { error, _ in
                    // Not confirmed - the next tick re-issues ._restore. On the
                    // late-reminder force-on path this retry is what guarantees
                    // the screen eventually comes back.
                    logger.warning("restore failed, will retry next tick: \(error.localizedDescription, privacy: .public)")
                }
                .cancellable(id: CancelID.work, cancelInFlight: true)

            case ._restoreConfirmed:
                state.isDimmed = false
                state.savedBrightness = nil
                return .none
            }
        }
    }
}
