import ComposableArchitecture
import Dao
import DependenciesTestSupport
import Foundation
import Testing

@testable import Dashboard

@MainActor
@Suite("AlertLoader Feature Tests", .dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
    $0.uuid = .incrementing
})
struct AlertLoaderTests {

    @Test("startMonitoring fires immediate tick then loops")
    func startMonitoring() async {
        let clock = TestClock()

        let store = TestStore(initialState: AlertLoaderFeature.State()) {
            AlertLoaderFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(Date())
            $0.calendar = .current
        }

        store.exhaustivity = .off

        await store.send(.startMonitoring)

        // Immediate tick
        await store.receive(\.tick)

        await store.finish()
    }

    @Test("tick computes late trackee names from state")
    func tickComputesFromState() async {
        let store = TestStore(initialState: AlertLoaderFeature.State()) {
            AlertLoaderFeature()
        } withDependencies: {
            $0.date = .constant(Date())
            $0.calendar = .current
        }

        // Seed data has no late reminders by default
        await store.send(.tick) {
            $0.lateTrackeeNames = []
            $0.dayOfWeek = Calendar.current.weekdaySymbols[
                Calendar.current.component(.weekday, from: Date()) - 1
            ]
        }
    }

    @Test("reminder lifecycle: not late, becomes late, tag scan clears alert")
    func reminderLifecycle() async throws {
        @Dependency(\.defaultDatabase) var database

        // Use a fixed UTC calendar so day-of-week calculations are deterministic
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!

        // April 5, 2026 is a Sunday
        // Reminder: Sunday at 12:00 PM
        // Late window: Sunday 12:00 PM - Sunday 4:00 PM

        // Start before the late window: Sunday 10:00 AM
        let beforeLateDate = cal.date(from: DateComponents(
            year: 2026, month: 4, day: 5, hour: 10, minute: 0
        ))!
        let currentDate = LockIsolated(beforeLateDate)

        // Get Alice from seed data
        let alice = try await database.read { db in
            try Trackee.all.fetchOne(db)!
        }

        // Insert a reminder for Alice: Sunday at 12:00 PM, no lastScan
        try await database.write { db in
            try ReminderTime.insert {
                ReminderTime.Draft(
                    weekDay: 1,  // Sunday
                    hour: 12,
                    minute: 0,
                    associatedTag: nil,
                    lastScan: nil,
                    trackeeId: alice.id
                )
            }.execute(db)
        }

        let store = TestStore(initialState: AlertLoaderFeature.State()) {
            AlertLoaderFeature()
        } withDependencies: {
            $0.date = DateGenerator { currentDate.value }
            $0.calendar = cal
        }

        // --- Tick 1: Sunday 10:00 AM — before the late window ---
        await store.send(.tick) {
            $0.dayOfWeek = cal.weekdaySymbols[0]
        }

        // --- Tick 2: Advance to Sunday 1:00 PM — inside the late window ---
        let duringLateDate = cal.date(from: DateComponents(
            year: 2026, month: 4, day: 5, hour: 13, minute: 0
        ))!
        currentDate.withValue { $0 = duringLateDate }

        await store.send(.tick) {
            $0.lateTrackeeNames = [alice.name]
        }

        // --- Simulate tag scan: delete and re-insert with lastScan set ---
        try await database.write { db in
            let reminder = try ReminderTime
                .where { $0.trackeeId.eq(alice.id) }
                .fetchAll(db)
                .first!
            try ReminderTime.find(reminder.id).delete().execute(db)
            try ReminderTime.insert {
                ReminderTime.Draft(
                    weekDay: 1,
                    hour: 12,
                    minute: 0,
                    associatedTag: nil,
                    lastScan: duringLateDate,
                    trackeeId: alice.id
                )
            }.execute(db)
        }

        // --- Tick 3: Still Sunday 1:00 PM — in late window but lastScan is fresh ---
        await store.send(.tick) {
            $0.lateTrackeeNames = []
        }
    }
}
