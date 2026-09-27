import AppTypes
import ComposableArchitecture
import Dao
import DependenciesTestSupport
import Foundation
import Testing

@testable import EditSettingsNew_TagLookup

@MainActor
@Suite("TagLookup Feature Tests", .dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
    $0.uuid = .incrementing
})
struct TagLookupTests {
    @Dependency(\.defaultDatabase) var database

    // Sunday April 5 2026, 12:30 UTC: inside the scan window of a Sunday
    // 12:00 reminder, so a dashboard scan WOULD credit it.
    let insideWindow = Date(timeIntervalSince1970: 1_775_392_200)
    let cup = TagSerial([0x01, 0x02, 0x03])

    private func seedAliceCup() async throws -> Trackee {
        try await database.write { [cup] db in
            let alice = try Trackee.where { $0.name.eq("Alice") }.fetchOne(db)!
            try ReminderTime.insert {
                ReminderTime.Draft(
                    weekDay: DaysOfWeek.Sunday.rawValue,
                    hour: 12,
                    minute: 0,
                    associatedTag: cup,
                    lastScan: nil,
                    trackeeId: alice.id
                )
            }.execute(db)
            return alice
        }
    }

    private func directory() async throws -> TagDirectory {
        try await database.read { db in
            TagDirectory(
                trackees: try Trackee.all.fetchAll(db),
                reminders: try ReminderTime.all.fetchAll(db)
            )
        }
    }

    @Test("a paired cup resolves to its owner and slot without crediting a dose")
    func pairedLookupIsReadOnly() async throws {
        let alice = try await seedAliceCup()
        let expected = try await directory()

        let store = TestStore(initialState: TagLookupFeature.State()) {
            TagLookupFeature()
        } withDependencies: { [insideWindow] in
            $0.date = .constant(insideWindow)
        }

        await store.send(._tagScanned(.tagPresent(cup))) {
            $0.lastReadAt = self.insideWindow
            $0.scannedTags = [self.cup]
        }
        await store.receive(\._lookupFinished) {
            $0.directory = expected
            $0.result = .paired(self.cup, expected.owners(of: self.cup))
        }

        guard case let .paired(_, owners) = store.state.result else {
            Issue.record("expected a paired result")
            return
        }
        #expect(owners.map(\.person.id) == [alice.id])
        #expect(owners.first?.cup.slots == ["12:00 PM · Sunday"])
        #expect(store.state.scannedCupCount == 1)
        #expect(store.state.totalCupCount == 1)

        let lastScans = try await database.read { db in
            try ReminderTime.all.fetchAll(db).map(\.lastScan)
        }
        #expect(lastScans == [nil])
    }

    @Test("an unknown tag reports unpaired and doesn't count toward the cup total")
    func unpairedTag() async throws {
        _ = try await seedAliceCup()
        let expected = try await directory()
        let stranger = TagSerial([0xDE, 0xAD])

        let store = TestStore(initialState: TagLookupFeature.State()) {
            TagLookupFeature()
        } withDependencies: { [insideWindow] in
            $0.date = .constant(insideWindow)
        }

        await store.send(._tagScanned(.tagPresent(stranger))) {
            $0.lastReadAt = self.insideWindow
            $0.scannedTags = [stranger]
        }
        await store.receive(\._lookupFinished) {
            $0.directory = expected
            $0.result = .unpaired(stranger)
        }
        #expect(store.state.scannedCupCount == 0)
        #expect(store.state.totalCupCount == 1)
    }

    @Test("an unreadable inside the bounce window keeps the owner but flags it")
    func bounceFlagged() async throws {
        var state = TagLookupFeature.State()
        state.result = .unpaired(cup)
        state.lastReadAt = insideWindow

        let store = TestStore(initialState: state) {
            TagLookupFeature()
        } withDependencies: { [insideWindow] in
            $0.date = .constant(insideWindow.addingTimeInterval(1))
        }

        // Could be a bounce of this cup OR a quick tap of a different one;
        // tagUnreadable carries no serial, so warn rather than guess.
        await store.send(._tagScanned(.tagUnreadable("bounce"))) {
            $0.newerTapFailed = true
        }
    }

    @Test("the next good read clears the newer-tap warning")
    func goodReadClearsWarning() async throws {
        _ = try await seedAliceCup()
        let expected = try await directory()
        var state = TagLookupFeature.State()
        state.result = .unpaired(TagSerial([0xDE, 0xAD]))
        state.newerTapFailed = true

        let store = TestStore(initialState: state) {
            TagLookupFeature()
        } withDependencies: { [insideWindow] in
            $0.date = .constant(insideWindow)
        }

        await store.send(._tagScanned(.tagPresent(cup))) {
            $0.lastReadAt = self.insideWindow
            $0.newerTapFailed = false
            $0.scannedTags = [self.cup]
        }
        await store.receive(\._lookupFinished) {
            $0.directory = expected
            $0.result = .paired(self.cup, expected.owners(of: self.cup))
        }
    }

    @Test("an unreadable after the bounce window clears the previous owner")
    func unreadableReplacesResult() async throws {
        var state = TagLookupFeature.State()
        state.result = .unpaired(cup)
        state.newerTapFailed = true
        state.lastReadAt = insideWindow

        let store = TestStore(initialState: state) {
            TagLookupFeature()
        } withDependencies: { [insideWindow] in
            $0.date = .constant(insideWindow.addingTimeInterval(5))
        }

        await store.send(._tagScanned(.tagUnreadable("hold it"))) {
            $0.result = .unreadable("hold it")
            $0.newerTapFailed = false
        }
    }

    @Test("noTag is silent; readerError surfaces as reader unavailable")
    func readerStates() async {
        let store = TestStore(initialState: TagLookupFeature.State()) {
            TagLookupFeature()
        }

        await store.send(._tagScanned(.noTag))
        await store.send(._tagScanned(.readerError("no reader"))) {
            $0.result = .readerUnavailable("no reader")
        }
    }

    @Test("onAppear loads the directory and feeds taps from the reader loop")
    func onAppearLoadsAndScans() async throws {
        _ = try await seedAliceCup()
        let expected = try await directory()
        let taps = LockIsolated(0)

        let store = TestStore(initialState: TagLookupFeature.State()) {
            TagLookupFeature()
        } withDependencies: { [cup, insideWindow] in
            $0.date = .constant(insideWindow)
            $0.tagReaderClient.nextTagId = {
                let n = taps.withValue { $0 += 1; return $0 }
                if n > 1 {
                    try? await Task.sleep(for: .seconds(100))
                    return .noTag
                }
                return .tagPresent(cup)
            }
        }
        store.exhaustivity = .off

        // The initial load and the first tap race (the stub reader answers
        // instantly), so assert the end state rather than their order.
        let appear = await store.send(.onAppear)
        await store.receive(\._lookupFinished) {
            $0.result = .paired(self.cup, expected.owners(of: self.cup))
        }
        await appear.cancel()
        #expect(store.state.directory == expected)
        #expect(store.state.scannedTags == [cup])
    }

    @Test("readerError backs the loop off instead of hot-looping")
    func readerErrorBacksOff() async {
        let clock = TestClock()
        let calls = LockIsolated(0)

        let store = TestStore(initialState: TagLookupFeature.State()) {
            TagLookupFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.tagReaderClient.nextTagId = {
                calls.withValue { $0 += 1 }
                return .readerError("dead")
            }
        }
        store.exhaustivity = .off

        let appear = await store.send(.onAppear)
        await store.receive(\._tagScanned)
        #expect(calls.value == 1)

        await clock.advance(by: .seconds(30))
        await store.receive(\._tagScanned)
        #expect(calls.value == 2)
        await appear.cancel()
    }

    @Test("reset clears the tick-off and the displayed result")
    func reset() async {
        var state = TagLookupFeature.State()
        state.scannedTags = [cup]
        state.result = .unpaired(cup)
        state.newerTapFailed = true
        state.lastReadAt = insideWindow

        let store = TestStore(initialState: state) {
            TagLookupFeature()
        }

        await store.send(.resetTapped) {
            $0.scannedTags = []
            $0.result = nil
            $0.newerTapFailed = false
            $0.lastReadAt = nil
        }
    }

    @Test("done dismisses the sheet")
    func doneDismisses() async {
        let dismissed = LockIsolated(false)
        let store = TestStore(initialState: TagLookupFeature.State()) {
            TagLookupFeature()
        } withDependencies: {
            $0.dismiss = DismissEffect { dismissed.setValue(true) }
        }

        await store.send(.doneTapped)
        #expect(dismissed.value)
    }
}
