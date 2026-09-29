/// Runs one action after a delay; scheduling again or cancelling drops the
/// pending one. LivePhotoView starts playback through this so a new player
/// never spins up while the crossfade's outgoing player is tearing down.
@MainActor
final class DeferredPlayback {
    private let clock: any Clock<Duration>
    private var pending: Task<Void, Never>?

    init(clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
    }

    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) {
        pending?.cancel()
        pending = Task { [clock] in
            try? await clock.sleep(for: delay)
            // Also catches a cancel that lands after the sleep finished but
            // before this resumed - dismantle must win that race.
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }
}
