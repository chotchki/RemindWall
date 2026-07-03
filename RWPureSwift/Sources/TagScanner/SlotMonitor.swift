/// The following code is littered with dragons in my mind.
///
/// It all stems from this bug: https://github.com/swiftlang/swift-corelibs-foundation/issues/3807
///  Which stops me from being able to use Swift 6 Observation to watch for tag scans.
///  I have filed Apple Feedback FB22134295 in an attempt to get Apple to fix it. I'm not holding out hope since the bug has existed
///  since at least 2018.
///
/// As a result, this code attempts to approach the problem by using Combine, which I can't find any effective help for. Which really
/// means I've leveraged Claude Code several times, I've rewritten chunks and then pointed Claude back it again. Call it advanced slop
/// but it might work.
///


import AppTypes
@preconcurrency import Combine
import CryptoTokenKit
import Foundation

private let GET_ID_APDU: Data = Data([0xFF, 0xCA, 0x00, 0x00, 0x04])

/// Attempts per tap: the tag can leave the RF field mid-read, so retry while the
/// slot still reports a valid card. Bounded — beginSession serializes across card
/// objects, so a runaway retry loop would also stall later taps.
private let DECODE_ATTEMPTS = 3

/// Holds Combine subscriptions outside the actor so the nonisolated init can
/// store into it without accessing actor-isolated state.
private final class CancellableStorage: @unchecked Sendable {
    var cancellables = Set<AnyCancellable>()
}

/// Waiter ids whose tasks were cancelled, recorded SYNCHRONOUSLY from the
/// nonisolated onCancel handler (the actor hop in cancelWaiter is async and can
/// lose the race with deliver()). deliver() consults this so a real tag event is
/// never resumed into a cancelled effect — TCA drops actions sent from cancelled
/// tasks, which silently ate the tap.
private final class CancelledWaiterIds: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: Set<UUID> = []

    func insert(_ id: UUID) {
        lock.withLock { _ = ids.insert(id) }
    }

    @discardableResult
    func remove(_ id: UUID) -> Bool {
        lock.withLock { ids.remove(id) != nil }
    }
}

/// Wrapper to shuttle a non-Sendable TKSmartCardSlot across isolation boundaries.
/// Safe because the slot is only read on the receiving side and not shared.
private struct SlotBox: @unchecked Sendable {
    let slot: TKSmartCardSlot
    let state: TKSmartCardSlot.State
}

@globalActor
actor SmartCardMonitor {
    public static let shared = SmartCardMonitor()

    //So we can notify on failures
    private let initSuccess: Bool

    private let storage = CancellableStorage()
    private let cancelledIds = CancelledWaiterIds()
    private var pendingContinuations: [UUID: CheckedContinuation<ReaderState, Never>] = [:]
    /// Buffers the last card event if it arrived when no one was waiting.
    /// TTL-bounded: with the dashboard loop stopped (settings visit) an event could
    /// otherwise sit here for minutes and replay as a live scan on return —
    /// falsely marking meds taken long after the physical tap.
    private var bufferedResult: ReaderState?
    private var bufferedAt: ContinuousClock.Instant?
    private let bufferTTL: Duration
    private let bufferClock = ContinuousClock()

    // MARK: - Init

    /// Test seam: a monitor with no CryptoTokenKit pipeline — events are injected
    /// straight into deliver(_:). Production always goes through `shared`.
    init(testing: Void, bufferTTL: Duration = .seconds(2)) {
        initSuccess = true
        self.bufferTTL = bufferTTL
    }

    private init() {
        bufferTTL = .seconds(2)
        guard let slotManager = TKSmartCardSlotManager.default else {
            initSuccess = false
            return
        }
        initSuccess = true

        slotManager.publisher(for: \.slotNames)
            .map { [weak slotManager] names -> AnyPublisher<SlotBox, Never> in
                guard let slotManager else { return Empty().eraseToAnyPublisher() }

                let slotPublishers: [AnyPublisher<SlotBox, Never>] = names.compactMap { name in
                    guard let slot = slotManager.slotNamed(name) else { return nil }

                    // muteCard means a tag reached the reader but never answered the
                    // ATR (marginal coupling, lifted mid-probe) — a physically-real tap
                    // that must produce feedback, not silence.
                    return slot.publisher(for: \.state)
                        .filter { $0 == .validCard || $0 == .muteCard }
                        .map { state in SlotBox(slot: slot, state: state) }
                        .eraseToAnyPublisher()
                }

                guard !slotPublishers.isEmpty else { return Empty().eraseToAnyPublisher() }
                return Publishers.MergeMany(slotPublishers).eraseToAnyPublisher()
            }
            .switchToLatest()
            .sink { box in
                Task.detached {
                    let state: ReaderState
                    if box.state == .muteCard {
                        state = .tagUnreadable("Tag did not answer — hold it against the reader")
                    } else {
                        state = await SmartCardMonitor.decodeCard(box.slot)
                    }
                    await SmartCardMonitor.shared.deliver(state)
                }
            }
            .store(in: &storage.cancellables)
    }

    // MARK: - Public API

    /// Suspends until the next time any slot transitions to `.validCard` or `.muteCard`.
    /// Multiple callers can wait concurrently; all are resumed when a card arrives.
    /// A cancelled caller is deregistered and resumed with `.noTag`.
    /// (nonisolated wrapper: the Swift 6 region checker rejects
    /// withTaskCancellationHandler inside actor isolation.)
    public nonisolated func nextValidCard() async -> ReaderState {
        let id = UUID()
        defer { cancelledIds.remove(id) }
        return await withTaskCancellationHandler {
            await self.awaitCard(id: id)
        } onCancel: {
            // Mark cancellation SYNCHRONOUSLY so deliver() never resumes a real tag
            // event into this dead task, then hop to the actor to deregister.
            self.cancelledIds.insert(id)
            Task { await self.cancelWaiter(id: id) }
        }
    }

    private func awaitCard(id: UUID) async -> ReaderState {
        guard initSuccess else {
            return .readerError("The slot monitor failed in start up")
        }

        // A cancelled caller must not consume the buffer — its effect would drop
        // the action and the tap would vanish. Leave the event for a live caller.
        guard !Task.isCancelled else {
            return .noTag
        }

        // If a card event arrived before anyone was waiting, return it immediately —
        // unless it has gone stale (nobody was consuming for a long stretch).
        if let buffered = bufferedResult, let at = bufferedAt {
            bufferedResult = nil
            bufferedAt = nil
            if bufferClock.now - at <= bufferTTL {
                return buffered
            }
        }

        return await withCheckedContinuation { continuation in
            if Task.isCancelled {
                continuation.resume(returning: .noTag)
            } else {
                self.pendingContinuations[id] = continuation
            }
        }
    }

    /// Removes and resumes a single waiter due to task cancellation.
    func cancelWaiter(id: UUID) {
        if let continuation = pendingContinuations.removeValue(forKey: id) {
            continuation.resume(returning: .noTag)
        }
    }

    /// Test-only visibility into waiter registration (cancellation deregisters asynchronously).
    var pendingWaiterCount: Int { pendingContinuations.count }

    // MARK: - Private

    /// Called when a card event arrives from the pipeline.
    /// Resumes all LIVE waiting callers with the result; waiters whose task was
    /// cancelled get `.noTag` (their effect would drop the action anyway). If no
    /// live waiter received it, the event is buffered for the next caller — but a
    /// buffered successful read is never downgraded: contactless taps can fire
    /// several state transitions (RF bounce), and a trailing failed decode must
    /// not destroy the `.tagPresent` a caller hasn't consumed yet.
    func deliver(_ state: ReaderState) {
        let continuations = pendingContinuations
        pendingContinuations.removeAll()

        var deliveredToLiveWaiter = false
        for (id, continuation) in continuations {
            if cancelledIds.remove(id) {
                continuation.resume(returning: .noTag)
            } else {
                continuation.resume(returning: state)
                deliveredToLiveWaiter = true
            }
        }

        guard !deliveredToLiveWaiter else { return }

        // Expire a stale buffer before the downgrade check, so an ancient
        // .tagPresent can't block a fresh failure from being recorded.
        if let at = bufferedAt, bufferClock.now - at > bufferTTL {
            bufferedResult = nil
            bufferedAt = nil
        }
        if case .tagPresent = bufferedResult, !state.isTagPresent {
            return
        }
        bufferedResult = state
        bufferedAt = bufferClock.now
    }

    private static func decodeCard(_ slot: TKSmartCardSlot) async -> ReaderState {
        var lastFailure: ReaderState = .tagUnreadable("Tag left the reader too soon — tap again and hold")

        for attempt in 1...DECODE_ATTEMPTS {
            switch await decodeAttempt(slot) {
            case .success(let state):
                return state
            case .failure(let state):
                lastFailure = state
            }

            // Retry only while the tag is still physically there.
            guard attempt < DECODE_ATTEMPTS, slot.state == .validCard else { break }
        }
        return lastFailure
    }

    private enum DecodeOutcome {
        case success(ReaderState)
        case failure(ReaderState)
    }

    private static func decodeAttempt(_ slot: TKSmartCardSlot) async -> DecodeOutcome {
        guard let card = slot.makeSmartCard() else {
            return .failure(.tagUnreadable("Tag left the reader too soon — tap again and hold"))
        }

        do {
            try await card.beginSession()
        } catch {
            return .failure(.tagUnreadable("Could not read tag: \(error.localizedDescription) — tap again and hold"))
        }

        defer {
            card.endSession()
        }

        guard let response = try? await card.transmit(GET_ID_APDU) else {
            return .failure(.tagUnreadable("Tag stopped answering — tap again and hold"))
        }

        if response.count < 2 {
            return .failure(.tagUnreadable("Tag reply too short — tap again and hold"))
        }

        let response_status = response.suffix(2)

        if response_status != Data([0x90, 0x00]) {
            let statusHex = response_status.map { String(format: "%02x", $0) }.joined()
            return .failure(.tagUnreadable("Tag reply error \(statusHex) — tap again and hold"))
        }

        let response_data = response.dropLast(2)

        if response_data.isEmpty {
            return .failure(.tagUnreadable("Tag sent no ID — tap again and hold"))
        }

        return .success(.tagPresent(TagSerial([UInt8](response_data))))
    }
}

extension ReaderState {
    fileprivate var isTagPresent: Bool {
        if case .tagPresent = self { return true }
        return false
    }
}
