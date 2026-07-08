import AppTypes
import ComposableArchitecture
import Dao
import Dependencies
import DependenciesTestSupport
import Foundation
import Testing

@testable import TagScanLoader

@MainActor
@Suite("TagScanLoader Feature Tests", .dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
    $0.uuid = .incrementing
    // Sound side effects are asserted in the dedicated sound tests below.
    $0.scanSoundPlayer = ScanSoundPlayer(playSuccess: {}, playFailure: {})
})
struct TagScanLoaderTests {

    @Test("startMonitoring begins continuous scanning")
    func startMonitoring() async {
        let scanCount = LockIsolated(0)

        let store = TestStore(initialState: TagScanLoaderFeature.State()) {
            TagScanLoaderFeature()
        } withDependencies: {
            $0.tagReaderClient.nextTagId = {
                scanCount.withValue { $0 += 1 }
                if scanCount.value > 1 {
                    // Block so the loop doesn't spin; finish() will cancel
                    try? await Task.sleep(for: .seconds(100))
                }
                return .noTag
            }
        }

        store.exhaustivity = .off

        await store.send(.startMonitoring)
        await store.receive(\._tagScanned)
        await store.finish()
    }

    @Test("re-sending startMonitoring cancels previous loop and starts new one")
    func restartMonitoring() async {
        let callCount = LockIsolated(0)

        let store = TestStore(initialState: TagScanLoaderFeature.State()) {
            TagScanLoaderFeature()
        } withDependencies: {
            $0.tagReaderClient.nextTagId = {
                callCount.withValue { $0 += 1 }
                // Block to simulate waiting for a card scan
                try? await Task.sleep(for: .seconds(100))
                return .noTag
            }
        }

        store.exhaustivity = .off

        // Start first monitoring loop
        await store.send(.startMonitoring)

        // Re-send startMonitoring — cancelInFlight cancels the first loop.
        // Before the fix, this scenario would crash with a precondition
        // failure in SmartCardMonitor.nextValidCard() because the cancelled
        // task left a pending continuation behind.
        await store.send(.startMonitoring)

        await store.finish()
    }

    @Test("noTag does not change state")
    func noTagIgnored() async {
        let store = TestStore(initialState: TagScanLoaderFeature.State()) {
            TagScanLoaderFeature()
        }

        await store.send(._tagScanned(.noTag))
    }

    @Test("readerError surfaces as an error overlay (no longer silently dropped)")
    func readerErrorSurfaces() async {
        let clock = TestClock()
        let store = TestStore(initialState: TagScanLoaderFeature.State()) {
            TagScanLoaderFeature()
        } withDependencies: {
            $0.continuousClock = clock
        }

        await store.send(._tagScanned(.readerError("Connection lost")))
        await store.receive(\._scanProcessed) {
            $0.scanResult = .error("Connection lost")
        }

        await clock.advance(by: .seconds(5))
        await store.receive(\.dismissResult) {
            $0.scanResult = nil
        }
    }

    @Test("tagUnreadable surfaces as tryAgain feedback")
    func tagUnreadableSurfaces() async {
        let clock = TestClock()
        let store = TestStore(initialState: TagScanLoaderFeature.State()) {
            TagScanLoaderFeature()
        } withDependencies: {
            $0.continuousClock = clock
        }

        await store.send(._tagScanned(.tagUnreadable("hold it steady")))
        await store.receive(\._scanProcessed) {
            $0.scanResult = .tryAgain("hold it steady")
        }

        await clock.advance(by: .seconds(5))
        await store.receive(\.dismissResult) {
            $0.scanResult = nil
        }
    }

    @Test("success plays the success sound, tryAgain plays failure, error plays nothing")
    func soundFeedback() async {
        let clock = TestClock()
        let successes = LockIsolated(0)
        let failures = LockIsolated(0)

        let store = TestStore(initialState: TagScanLoaderFeature.State()) {
            TagScanLoaderFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.scanSoundPlayer = ScanSoundPlayer(
                playSuccess: { successes.withValue { $0 += 1 } },
                playFailure: { failures.withValue { $0 += 1 } }
            )
        }
        store.exhaustivity = .off

        await store.send(._scanProcessed(.success("Alice")))
        await store.send(._scanProcessed(.tryAgain("hold")))
        await store.send(._scanProcessed(.error("db broke")))

        // Let the (cancelInFlight-coalesced) auto-dismiss fire, then drain all
        // effects so the sound counters are final before asserting.
        await clock.advance(by: .seconds(5))
        await store.finish()

        #expect(successes.value == 1)
        #expect(failures.value == 1)
    }

    @Test("stopMonitoring cancels the scan loop, the auto-dismiss, and clears the overlay")
    func stopMonitoring() async {
        let clock = TestClock()
        let store = TestStore(initialState: TagScanLoaderFeature.State()) {
            TagScanLoaderFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.tagReaderClient.nextTagId = {
                try? await Task.sleep(for: .seconds(100))
                return .noTag
            }
        }
        store.exhaustivity = .off

        await store.send(.startMonitoring)
        await store.send(._scanProcessed(.success("Alice"))) {
            $0.scanResult = .success("Alice")
        }

        await store.send(.stopMonitoring) {
            $0.scanResult = nil
        }

        // Cancelled auto-dismiss: advancing past 5s must produce no dismissResult.
        await clock.advance(by: .seconds(10))
        await store.finish()
    }

    @Test("reader errors back off instead of hot-looping")
    func readerErrorBackoff() async {
        let clock = TestClock()
        let calls = LockIsolated(0)

        let store = TestStore(initialState: TagScanLoaderFeature.State()) {
            TagScanLoaderFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.tagReaderClient.nextTagId = {
                calls.withValue { $0 += 1 }
                return .readerError("reader is dead")
            }
        }
        store.exhaustivity = .off

        await store.send(.startMonitoring)
        await store.receive(\._scanProcessed)
        #expect(calls.value == 1)

        // Second poll happens only after the 30s backoff, not immediately.
        await clock.advance(by: .seconds(30))
        await store.receive(\._tagScanned)
        #expect(calls.value == 2)

        await store.send(.stopMonitoring)
        await store.finish()
    }

    @Test("tag not found in database shows unknownTag")
    func unknownTag() async {
        let clock = TestClock()
        let unknownSerial = TagSerial([0xFF, 0xEE, 0xDD])

        let store = TestStore(initialState: TagScanLoaderFeature.State()) {
            TagScanLoaderFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(Date())
            $0.calendar = .current
        }

        await store.send(._tagScanned(.tagPresent(unknownSerial)))
        await store.receive(\._scanProcessed) {
            $0.scanResult = .unknownTag
        }

        await clock.advance(by: .seconds(5))
        await store.receive(\.dismissResult) {
            $0.scanResult = nil
        }
    }

    @Test("tag found but outside scan window shows wrongScanWindow")
    func wrongScanWindow() async throws {
        @Dependency(\.defaultDatabase) var database

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!

        let clock = TestClock()

        // April 6, 2026 is a Monday -- outside scan window for Sunday 12:00 PM reminder
        let outsideWindow = cal.date(from: DateComponents(
            year: 2026, month: 4, day: 6, hour: 10, minute: 0
        ))!

        let testTag = TagSerial([0xAA, 0xBB])

        let alice = try await database.read { db in
            try Trackee.all.fetchOne(db)!
        }

        try await database.write { db in
            try ReminderTime.insert {
                ReminderTime.Draft(
                    weekDay: 1,  // Sunday
                    hour: 12,
                    minute: 0,
                    associatedTag: testTag,
                    lastScan: nil,
                    trackeeId: alice.id
                )
            }.execute(db)
        }

        let store = TestStore(initialState: TagScanLoaderFeature.State()) {
            TagScanLoaderFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = DateGenerator { outsideWindow }
            $0.calendar = cal
        }

        await store.send(._tagScanned(.tagPresent(testTag)))
        await store.receive(\._scanProcessed) {
            $0.scanResult = .wrongScanWindow
        }

        await clock.advance(by: .seconds(5))
        await store.receive(\.dismissResult) {
            $0.scanResult = nil
        }
    }

    @Test("tag found and scannable updates lastScan and shows success")
    func successfulScan() async throws {
        @Dependency(\.defaultDatabase) var database

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!

        let clock = TestClock()

        // Sunday 12:30 PM -- inside scan window for Sunday 12:00 PM reminder
        let insideWindow = cal.date(from: DateComponents(
            year: 2026, month: 4, day: 5, hour: 12, minute: 30
        ))!

        let testTag = TagSerial([0x01, 0x02, 0x03])

        let alice = try await database.read { db in
            try Trackee.all.fetchOne(db)!
        }

        try await database.write { db in
            try ReminderTime.insert {
                ReminderTime.Draft(
                    weekDay: 1,  // Sunday
                    hour: 12,
                    minute: 0,
                    associatedTag: testTag,
                    lastScan: nil,
                    trackeeId: alice.id
                )
            }.execute(db)
        }

        let store = TestStore(initialState: TagScanLoaderFeature.State()) {
            TagScanLoaderFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = DateGenerator { insideWindow }
            $0.calendar = cal
        }

        await store.send(._tagScanned(.tagPresent(testTag)))
        await store.receive(\._scanProcessed) {
            $0.scanResult = .success(alice.name)
        }

        // Verify lastScan was updated in database
        let updatedReminder = try await database.read { db in
            let all = try ReminderTime.all.fetchAll(db)
            return all.first { $0.associatedTag == testTag }
        }
        #expect(updatedReminder?.lastScan == insideWindow)

        await clock.advance(by: .seconds(5))
        await store.receive(\.dismissResult) {
            $0.scanResult = nil
        }
    }

    @Test("a soft-disabled trackee's tag still scans successfully — pausing gates the nag, not the scan")
    func disabledTrackeeStillScans() async throws {
        @Dependency(\.defaultDatabase) var database

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!

        let clock = TestClock()

        // Sunday 12:30 PM -- inside scan window for a Sunday 12:00 PM reminder.
        let insideWindow = cal.date(from: DateComponents(
            year: 2026, month: 4, day: 5, hour: 12, minute: 30
        ))!

        let testTag = TagSerial([0xD1, 0x5A, 0xB1])

        let alice = try await database.read { db in
            try Trackee.all.fetchOne(db)!
        }

        try await database.write { db in
            try ReminderTime.insert {
                ReminderTime.Draft(
                    weekDay: 1,  // Sunday
                    hour: 12,
                    minute: 0,
                    associatedTag: testTag,
                    lastScan: nil,
                    trackeeId: alice.id
                )
            }.execute(db)
            // Soft-disable Alice: no dashboard nag, but her tag must still credit.
            try Trackee.find(alice.id)
                .update { $0.remindersEnabled = false }
                .execute(db)
        }

        let store = TestStore(initialState: TagScanLoaderFeature.State()) {
            TagScanLoaderFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = DateGenerator { insideWindow }
            $0.calendar = cal
        }

        await store.send(._tagScanned(.tagPresent(testTag)))
        await store.receive(\._scanProcessed) {
            $0.scanResult = .success(alice.name)
        }

        // The dose is still recorded even though Alice is paused.
        let updatedReminder = try await database.read { db in
            try ReminderTime.all.fetchAll(db).first { $0.associatedTag == testTag }
        }
        #expect(updatedReminder?.lastScan == insideWindow)

        await clock.advance(by: .seconds(5))
        await store.receive(\.dismissResult) {
            $0.scanResult = nil
        }
    }

    @Test("two reminders sharing one tag: the currently-scannable one gets credited")
    func duplicateTagPrefersScannable() async throws {
        @Dependency(\.defaultDatabase) var database

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!

        let clock = TestClock()

        // Monday April 6, 2026, 12:30 -- inside the window for the MONDAY reminder only
        let mondayLunch = cal.date(from: DateComponents(
            year: 2026, month: 4, day: 6, hour: 12, minute: 30
        ))!

        let sharedTag = TagSerial([0xCA, 0xFE])

        let alice = try await database.read { db in
            try Trackee.all.fetchOne(db)!
        }

        try await database.write { db in
            // Sunday reminder inserted FIRST so fetch order would pick it —
            // the old first(where:) bug reported wrongScanWindow here.
            try ReminderTime.insert {
                ReminderTime.Draft(
                    weekDay: 1,  // Sunday
                    hour: 12,
                    minute: 0,
                    associatedTag: sharedTag,
                    lastScan: nil,
                    trackeeId: alice.id
                )
            }.execute(db)
            try ReminderTime.insert {
                ReminderTime.Draft(
                    weekDay: 2,  // Monday
                    hour: 12,
                    minute: 0,
                    associatedTag: sharedTag,
                    lastScan: nil,
                    trackeeId: alice.id
                )
            }.execute(db)
        }

        let store = TestStore(initialState: TagScanLoaderFeature.State()) {
            TagScanLoaderFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = DateGenerator { mondayLunch }
            $0.calendar = cal
        }

        await store.send(._tagScanned(.tagPresent(sharedTag)))
        await store.receive(\._scanProcessed) {
            $0.scanResult = .success(alice.name)
        }

        let reminders = try await database.read { db in
            try ReminderTime.all.fetchAll(db).filter { $0.associatedTag == sharedTag }
        }
        let monday = reminders.first { $0.weekDay == 2 }
        let sunday = reminders.first { $0.weekDay == 1 }
        #expect(monday?.lastScan == mondayLunch)
        #expect(sunday?.lastScan == nil)

        await clock.advance(by: .seconds(5))
        await store.receive(\.dismissResult) {
            $0.scanResult = nil
        }
    }

    @Test("database failure surfaces as an error overlay instead of a silent drop")
    func databaseErrorSurfaces() async throws {
        @Dependency(\.defaultDatabase) var database

        let clock = TestClock()

        // Force every reminder query to throw.
        try await database.write { db in
            try db.execute(sql: #"DROP TABLE "reminderTimes""#)
        }

        let store = TestStore(initialState: TagScanLoaderFeature.State()) {
            TagScanLoaderFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(Date())
            $0.calendar = .current
        }
        // The error string comes from the database layer — assert the case, not the text.
        store.exhaustivity = .off

        await store.send(._tagScanned(.tagPresent(TagSerial([0x01]))))
        await store.receive(\._scanProcessed)
        #expect({
            if case .error = store.state.scanResult { return true }
            return false
        }())

        await clock.advance(by: .seconds(5))
        await store.receive(\.dismissResult)
        #expect(store.state.scanResult == nil)
    }

    @Test("trailing RF-bounce failure does not replace a showing success overlay")
    func bounceDoesNotStompSuccess() async {
        var initialState = TagScanLoaderFeature.State()
        initialState.scanResult = .success("Alice")

        let store = TestStore(initialState: initialState) {
            TagScanLoaderFeature()
        }

        // Same physical tap, trailing failed decode — must be swallowed.
        await store.send(._tagScanned(.tagUnreadable("bounce")))
    }

    @Test("overlapping windows: the not-yet-scanned reminder is credited, not the one just scanned")
    func prefersUnscannedAmongScannable() async throws {
        @Dependency(\.defaultDatabase) var database

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!

        let clock = TestClock()

        // Monday 12:30 — both Monday reminders (12:00 and 12:15) are in-window.
        let mondayLunch = cal.date(from: DateComponents(
            year: 2026, month: 4, day: 6, hour: 12, minute: 30
        ))!
        let earlierScan = cal.date(from: DateComponents(
            year: 2026, month: 4, day: 6, hour: 12, minute: 5
        ))!

        let sharedTag = TagSerial([0xBE, 0xEF])

        let alice = try await database.read { db in
            try Trackee.all.fetchOne(db)!
        }

        try await database.write { db in
            // Already scanned at 12:05 — inserted first so naive pick order hits it.
            try ReminderTime.insert {
                ReminderTime.Draft(
                    weekDay: 2, hour: 12, minute: 0,
                    associatedTag: sharedTag,
                    lastScan: earlierScan,
                    trackeeId: alice.id
                )
            }.execute(db)
            try ReminderTime.insert {
                ReminderTime.Draft(
                    weekDay: 2, hour: 12, minute: 15,
                    associatedTag: sharedTag,
                    lastScan: nil,
                    trackeeId: alice.id
                )
            }.execute(db)
        }

        let store = TestStore(initialState: TagScanLoaderFeature.State()) {
            TagScanLoaderFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = DateGenerator { mondayLunch }
            $0.calendar = cal
        }

        await store.send(._tagScanned(.tagPresent(sharedTag)))
        await store.receive(\._scanProcessed) {
            $0.scanResult = .success(alice.name)
        }

        let reminders = try await database.read { db in
            try ReminderTime.all.fetchAll(db).filter { $0.associatedTag == sharedTag }
        }
        let unscanned = reminders.first { $0.minute == 15 }
        let alreadyScanned = reminders.first { $0.minute == 0 }
        #expect(unscanned?.lastScan == mondayLunch)
        #expect(alreadyScanned?.lastScan == earlierScan)

        await clock.advance(by: .seconds(5))
        await store.receive(\.dismissResult) {
            $0.scanResult = nil
        }
    }

    @Test("dismissResult clears scanResult")
    func tapDismiss() async {
        var initialState = TagScanLoaderFeature.State()
        initialState.scanResult = .success("Alice")

        let store = TestStore(initialState: initialState) {
            TagScanLoaderFeature()
        }

        await store.send(.dismissResult) {
            $0.scanResult = nil
        }
    }

    @Test("new scan result cancels previous auto-dismiss timer")
    func newScanCancelsPreviousTimer() async throws {
        @Dependency(\.defaultDatabase) var database

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!

        let clock = TestClock()

        let insideWindow = cal.date(from: DateComponents(
            year: 2026, month: 4, day: 5, hour: 12, minute: 30
        ))!

        let tag1 = TagSerial([0x01])
        let tag2 = TagSerial([0xFF, 0xEE])  // unknown tag

        let alice = try await database.read { db in
            try Trackee.all.fetchOne(db)!
        }

        try await database.write { db in
            try ReminderTime.insert {
                ReminderTime.Draft(
                    weekDay: 1,
                    hour: 12,
                    minute: 0,
                    associatedTag: tag1,
                    lastScan: nil,
                    trackeeId: alice.id
                )
            }.execute(db)
        }

        let store = TestStore(initialState: TagScanLoaderFeature.State()) {
            TagScanLoaderFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = DateGenerator { insideWindow }
            $0.calendar = cal
        }

        // First scan: success
        await store.send(._tagScanned(.tagPresent(tag1)))
        await store.receive(\._scanProcessed) {
            $0.scanResult = .success(alice.name)
        }

        // Advance 3 seconds (less than 5)
        await clock.advance(by: .seconds(3))

        // Second scan: unknown tag (cancels the first auto-dismiss)
        await store.send(._tagScanned(.tagPresent(tag2)))
        await store.receive(\._scanProcessed) {
            $0.scanResult = .unknownTag
        }

        // Advance 5 seconds from the second scan
        await clock.advance(by: .seconds(5))
        await store.receive(\.dismissResult) {
            $0.scanResult = nil
        }
    }
}
