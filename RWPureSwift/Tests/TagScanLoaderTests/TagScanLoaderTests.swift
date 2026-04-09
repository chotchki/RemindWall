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

    @Test("noTag does not change state")
    func noTagIgnored() async {
        let store = TestStore(initialState: TagScanLoaderFeature.State()) {
            TagScanLoaderFeature()
        }

        await store.send(._tagScanned(.noTag))
    }

    @Test("readerError does not change state")
    func readerErrorIgnored() async {
        let store = TestStore(initialState: TagScanLoaderFeature.State()) {
            TagScanLoaderFeature()
        }

        await store.send(._tagScanned(.readerError("Connection lost")))
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
