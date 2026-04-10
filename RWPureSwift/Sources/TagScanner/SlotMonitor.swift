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

/// Holds Combine subscriptions outside the actor so the nonisolated init can
/// store into it without accessing actor-isolated state.
private final class CancellableStorage: @unchecked Sendable {
    var cancellables = Set<AnyCancellable>()
}

/// Wrapper to shuttle a non-Sendable TKSmartCardSlot across isolation boundaries.
/// Safe because the slot is only read on the receiving side and not shared.
private struct SlotBox: @unchecked Sendable {
    let slot: TKSmartCardSlot
}

@globalActor
actor SmartCardMonitor {
    public static let shared = SmartCardMonitor()

    //So we can notify on failures
    private let initSuccess: Bool

    private let storage = CancellableStorage()
    private var pendingContinuations: [UUID: CheckedContinuation<ReaderState, Never>] = [:]

    // MARK: - Init

    private init() {
        guard let slotManager = TKSmartCardSlotManager.default else {
            initSuccess = false
            return
        }
        initSuccess = true

        slotManager.publisher(for: \.slotNames)
            .map { [weak slotManager] names -> AnyPublisher<TKSmartCardSlot, Never> in
                guard let slotManager else { return Empty().eraseToAnyPublisher() }

                let slotPublishers: [AnyPublisher<TKSmartCardSlot, Never>] = names.compactMap { name in
                    guard let slot = slotManager.slotNamed(name) else { return nil }

                    return slot.publisher(for: \.state)
                        .filter { $0 == .validCard }
                        .map { _ in slot }
                        .eraseToAnyPublisher()
                }

                guard !slotPublishers.isEmpty else { return Empty().eraseToAnyPublisher() }
                return Publishers.MergeMany(slotPublishers).eraseToAnyPublisher()
            }
            .switchToLatest()
            .sink { slot in
                let box = SlotBox(slot: slot)
                Task.detached {
                    let state = await SmartCardMonitor.decodeCard(box.slot)
                    await SmartCardMonitor.shared.deliver(state)
                }
            }
            .store(in: &storage.cancellables)
    }

    // MARK: - Public API

    /// Suspends until the next time any slot transitions to `.validCard`.
    /// Multiple callers can wait concurrently; all are resumed when a card arrives.
    /// Events that arrive when no caller is waiting are silently dropped.
    public func nextValidCard() async -> ReaderState {
        guard initSuccess else {
            return .readerError("The slot monitor failed in start up")
        }

        let id = UUID()
        return await withCheckedContinuation { continuation in
            if Task.isCancelled {
                continuation.resume(returning: .noTag)
            } else {
                self.pendingContinuations[id] = continuation
            }
        }
    }

    // MARK: - Private

    /// Called when a valid card event arrives from the pipeline.
    /// Resumes all waiting callers with the same result.
    private func deliver(_ state: ReaderState) {
        guard !pendingContinuations.isEmpty else {
            // Nobody waiting — drop the event.
            return
        }
        let continuations = pendingContinuations
        pendingContinuations.removeAll()
        for (_, continuation) in continuations {
            continuation.resume(returning: state)
        }
    }

    private static func decodeCard(_ slot: TKSmartCardSlot) async -> ReaderState {
        guard let card = slot.makeSmartCard() else {
            return .noTag
        }

        do {
            try await card.beginSession()
        } catch {
            return .readerError("Could not start session: \(error)")
        }

        defer {
            card.endSession()
        }

        guard let response = try? await card.transmit(GET_ID_APDU) else {
            return .readerError("Unable to query tag")
        }

        if response.count < 2 {
            return .readerError("Response too short \(response)")
        }

        let response_status = response.suffix(2)

        if response_status != Data([0x90, 0x00]) {
            return .readerError("Response status \(response_status) error")
        }

        let response_data = response.dropLast(2)

        if response_data.isEmpty {
            return .readerError("No Tag ID found")
        }

        return .tagPresent(TagSerial([UInt8](response_data)))
    }
}

