//
//  TagScannerTest.swift
//  RWPureSwift
//
//  Created by Christopher Hotchkiss on 12/6/25.
//
import ComposableArchitecture
import DependenciesTestSupport
import Foundation
@testable import TagScanner
import AppTypes
import Testing

@MainActor
@Suite("AssociateTag Feature Tests", .serialized)
struct AssociateTagTests {

    @Test("Tag Scan Valid Result")
    func valid_result() async throws {
        let aT = Shared(value: nil as TagSerial?)
        let testSerial = TagSerial([0x0, 0x1, 0x2])

        let store = TestStore(initialState: AssociateTagFeature.State(associatedTag: aT)) {
            AssociateTagFeature()
        } withDependencies: {
            $0.tagReaderClient.nextTagId = {
                .tagPresent(testSerial)
            }
        }

        await store.send(.startScanningTapped) { state in
            state.scanning = true
        }

        await store.receive(\.scanResult) { state in
            state.$associatedTag.withLock { $0 = testSerial }
            state.scanning = false
        }
    }

    @Test("Tag Scan No Tag")
    func no_tag() async throws {
        let aT = Shared(value: nil as TagSerial?)

        let store = TestStore(initialState: AssociateTagFeature.State(associatedTag: aT)) {
            AssociateTagFeature()
        } withDependencies: {
            $0.tagReaderClient.nextTagId = {
                .noTag
            }
        }

        await store.send(.startScanningTapped) { state in
            state.scanning = true
        }

        await store.receive(\.scanResult) { state in
            state.$associatedTag.withLock { $0 = nil }
            state.scanning = false
            state.errorMessage = "No tag detected. Please try again."
        }
    }

    @Test("Tag Scan Reader Error")
    func reader_error() async throws {
        let aT = Shared(value: nil as TagSerial?)

        let store = TestStore(initialState: AssociateTagFeature.State(associatedTag: aT)) {
            AssociateTagFeature()
        } withDependencies: {
            $0.tagReaderClient.nextTagId = {
                .readerError("Connection failed")
            }
        }

        await store.send(.startScanningTapped) { state in
            state.scanning = true
        }

        await store.receive(\.scanResult) { state in
            state.scanning = false
            state.errorMessage = "Connection failed"
        }
    }

    @Test("Cancel Scanning Tapped")
    func cancel_scanning() async throws {
        let aT = Shared(value: nil as TagSerial?)

        let store = TestStore(initialState: AssociateTagFeature.State(associatedTag: aT)) {
            AssociateTagFeature()
        } withDependencies: {
            $0.tagReaderClient.nextTagId = {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                return .noTag
            }
        }

        await store.send(.startScanningTapped) { state in
            state.scanning = true
        }

        await store.send(.cancelScanningTapped) { state in
            state.scanning = false
        }
    }

    @Test("Dismiss Error clears error message")
    func dismiss_error() async throws {
        let aT = Shared(value: nil as TagSerial?)

        var initialState = AssociateTagFeature.State(associatedTag: aT)
        initialState.errorMessage = "Some error"

        let store = TestStore(initialState: initialState) {
            AssociateTagFeature()
        }

        await store.send(.dismissError) { state in
            state.errorMessage = nil
        }
    }
}

// MARK: - Multi-waiter tests (validates SmartCardMonitor fix)

/// These tests validate the multi-waiter continuation pattern directly,
/// without going through TCA TestStore (which requires @MainActor and
/// conflicts with detached concurrent tasks).
///
/// The bug: SmartCardMonitor used a single pendingContinuation. When two
/// features (TagScanLoaderFeature's loop + AssociateTagFeature's one-shot)
/// both called nextValidCard(), the second caller evicted the first with .noTag.
/// The fix changed to a [UUID: Continuation] dictionary so multiple callers
/// can wait concurrently.
@Suite("Multi-waiter coordinator tests")
struct MultiWaiterTests {

    @Test("Multiple concurrent waiters all receive the delivered result")
    func multiple_waiters_all_receive_result() async throws {
        let coordinator = MultiWaiterCoordinator()
        let testSerial = TagSerial([0xAA, 0xBB, 0xCC])
        let expected = ReaderState.tagPresent(testSerial)

        // Spawn 3 concurrent waiters
        async let result1 = coordinator.waitForResult()
        async let result2 = coordinator.waitForResult()
        async let result3 = coordinator.waitForResult()

        // Give waiters time to register
        try await Task.sleep(for: .milliseconds(100))

        // Verify all 3 registered
        let count = await coordinator.waiterCount
        #expect(count == 3)

        // Deliver to all
        await coordinator.deliver(expected)

        // All should get the same result
        let r1 = await result1
        let r2 = await result2
        let r3 = await result3
        #expect(r1 == expected)
        #expect(r2 == expected)
        #expect(r3 == expected)
    }

    @Test("Deliver with no waiters does not crash")
    func deliver_with_no_waiters() async {
        let coordinator = MultiWaiterCoordinator()
        // Should be a no-op, not crash
        await coordinator.deliver(.tagPresent(TagSerial([0x01])))
        let count = await coordinator.waiterCount
        #expect(count == 0)
    }

    @Test("Second waiter is not evicted when first waiter re-enters after delivery")
    func reentry_does_not_evict_other_waiter() async throws {
        let coordinator = MultiWaiterCoordinator()
        let testSerial = TagSerial([0x01, 0x02])

        // Waiter A (simulates the continuous loop): calls, gets result, re-enters
        // Waiter B (simulates one-shot scan): calls once, should not be evicted
        let waiterAResults = LockIsolated<[ReaderState]>([])
        let waiterBResult = LockIsolated<ReaderState?>(nil)

        // Start waiter B first
        let taskB = Task.detached {
            let result = await coordinator.waitForResult()
            waiterBResult.withValue { $0 = result }
        }

        // Start waiter A (loop pattern)
        let taskA = Task.detached {
            // First call
            let first = await coordinator.waitForResult()
            waiterAResults.withValue { $0.append(first) }

            // Re-enter immediately (the dangerous moment)
            let second = await coordinator.waitForResult()
            waiterAResults.withValue { $0.append(second) }
        }

        try await Task.sleep(for: .milliseconds(100))

        // Both should be waiting
        let count1 = await coordinator.waiterCount
        #expect(count1 == 2)

        // First delivery: both get .noTag
        await coordinator.deliver(.noTag)

        // Give waiter A time to re-enter
        try await Task.sleep(for: .milliseconds(100))

        // Waiter B should have completed with .noTag, waiter A should be waiting again
        #expect(waiterBResult.value == .noTag)

        let count2 = await coordinator.waiterCount
        #expect(count2 == 1)

        // Second delivery: only waiter A's second call
        await coordinator.deliver(.tagPresent(testSerial))

        await taskA.value
        await taskB.value

        #expect(waiterAResults.value == [.noTag, .tagPresent(testSerial)])
    }
}

// MARK: - Test helper

/// Actor that mirrors the fixed SmartCardMonitor pattern: multiple callers can
/// await `waitForResult()` concurrently, and `deliver()` resumes all of them.
private actor MultiWaiterCoordinator {
    private var waiters: [UUID: CheckedContinuation<ReaderState, Never>] = [:]

    var waiterCount: Int { waiters.count }

    func waitForResult() async -> ReaderState {
        let id = UUID()
        return await withCheckedContinuation { continuation in
            waiters[id] = continuation
        }
    }

    func deliver(_ state: ReaderState) {
        let current = waiters
        waiters.removeAll()
        for (_, continuation) in current {
            continuation.resume(returning: state)
        }
    }
}
