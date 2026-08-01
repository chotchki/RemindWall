import AppTypes
import Dao
import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import Sharing
import StructuredQueries
import Testing

@MainActor
@Suite("Synced Setting Tests")
struct SyncedSettingTests {
    @Test("Bool round-trips through the settings table")
    func boolRoundTrip() async throws {
        let fixedDate = Date(timeIntervalSince1970: 1000)
        try await withDependencies {
            $0.uuid = .incrementing
            $0.date = .constant(fixedDate)
            $0.defaultDatabase = try! $0.appDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var defaultDatabase
            @Shared(.syncedSetting("busAlertsEnabled")) var enabled: Bool = false
            #expect(enabled == false)

            $enabled.withLock { $0 = true }
            try await $enabled.save()

            let rows = try await defaultDatabase.read { db in
                try Setting.where { $0.key.eq("busAlertsEnabled") }.fetchAll(db)
            }
            #expect(rows.count == 1)
            #expect(rows.first?.value == "true")
            #expect(rows.first?.lastModified == fixedDate)
        }
    }

    @Test("Optional tagged value round-trips and nil deletes the row")
    func optionalTaggedRoundTrip() async throws {
        try await withDependencies {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1000))
            $0.defaultDatabase = try! $0.appDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var defaultDatabase
            @Shared(.syncedSetting("screenOffSchedule")) var schedule: ScreenOffSchedule?
            #expect(schedule == nil)

            $schedule.withLock { $0 = .default }
            try await $schedule.save()

            let stored = try await defaultDatabase.read { db in
                try Setting.where { $0.key.eq("screenOffSchedule") }.fetchOne(db)
            }
            #expect(stored?.value == ScreenOffSchedule.default.rawValue)

            $schedule.withLock { $0 = nil }
            try await $schedule.save()

            let afterNil = try await defaultDatabase.read { db in
                try Setting.where { $0.key.eq("screenOffSchedule") }.fetchAll(db)
            }
            #expect(afterNil.isEmpty)
        }
    }

    @Test("Later write wins when duplicate rows exist for a key")
    func laterWriteWins() async throws {
        try await withDependencies {
            $0.uuid = .incrementing
            $0.defaultDatabase = try! $0.appDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var defaultDatabase
            @Dependency(\.uuid) var uuid

            // Two rows for one key, as CloudKit-merged concurrent first-writes
            // from two devices would leave behind.
            try await defaultDatabase.write { db in
                try Setting.insert {
                    Setting(
                        id: Setting.ID(uuid()),
                        key: "conflicted",
                        value: "older",
                        lastModified: Date(timeIntervalSince1970: 1000)
                    )
                    Setting(
                        id: Setting.ID(uuid()),
                        key: "conflicted",
                        value: "newer",
                        lastModified: Date(timeIntervalSince1970: 2000)
                    )
                }.execute(db)
            }

            @Shared(.syncedSetting("conflicted")) var value: String = "default"
            #expect(value == "newer")
        }
    }

    @Test("An external database write updates the shared value")
    func externalWriteObserved() async throws {
        try await withDependencies {
            $0.uuid = .incrementing
            $0.defaultDatabase = try! $0.appDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var defaultDatabase
            @Dependency(\.uuid) var uuid

            @Shared(.syncedSetting("observed")) var value: String = "default"
            #expect(value == "default")

            // Simulates the SyncEngine applying a remote device's write.
            try await defaultDatabase.write { db in
                try Setting.insert {
                    Setting(
                        id: Setting.ID(uuid()),
                        key: "observed",
                        value: "remote",
                        lastModified: Date(timeIntervalSince1970: 2000)
                    )
                }.execute(db)
            }

            let shared = $value
            try await eventually { shared.wrappedValue == "remote" }
            #expect(value == "remote")
        }
    }

    @Test("Repeated saves keep a single row with a stable id")
    func repeatedSavesSingleRow() async throws {
        try await withDependencies {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1000))
            $0.defaultDatabase = try! $0.appDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var defaultDatabase
            @Shared(.syncedSetting("rewritten")) var value: Int = 0

            $value.withLock { $0 = 1 }
            try await $value.save()
            let firstID = try await defaultDatabase.read { db in
                try Setting.where { $0.key.eq("rewritten") }.fetchOne(db)?.id
            }

            $value.withLock { $0 = 2 }
            try await $value.save()
            let rows = try await defaultDatabase.read { db in
                try Setting.where { $0.key.eq("rewritten") }.fetchAll(db)
            }
            #expect(rows.count == 1)
            #expect(rows.first?.value == "2")
            #expect(rows.first?.id == firstID)
        }
    }

    @Test("Rapid successive writes never revert to the earlier value")
    func rapidWritesKeepLatest() async throws {
        try await withDependencies {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1000))
            $0.defaultDatabase = try! $0.appDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var defaultDatabase
            @Shared(.syncedSetting("rapid")) var value: String = "default"

            // The first save's observation echo must not clobber the second
            // in-memory write while its own save is still in flight.
            $value.withLock { $0 = "one" }
            $value.withLock { $0 = "two" }
            try await $value.save()
            try await Task.sleep(for: .milliseconds(100))

            #expect(value == "two")
            let stored = try await defaultDatabase.read { db in
                try Setting.where { $0.key.eq("rapid") }.fetchOne(db)?.value
            }
            #expect(stored == "two")
        }
    }

    @Test("A save through the key cleans up duplicate rows for its key")
    func saveHealsDuplicateRows() async throws {
        try await withDependencies {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 3000))
            $0.defaultDatabase = try! $0.appDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var defaultDatabase
            @Dependency(\.uuid) var uuid

            try await defaultDatabase.write { db in
                try Setting.insert {
                    Setting(
                        id: Setting.ID(uuid()),
                        key: "healed",
                        value: "stray-a",
                        lastModified: Date(timeIntervalSince1970: 1000)
                    )
                    Setting(
                        id: Setting.ID(uuid()),
                        key: "healed",
                        value: "stray-b",
                        lastModified: Date(timeIntervalSince1970: 2000)
                    )
                }.execute(db)
            }

            @Shared(.syncedSetting("healed")) var value: String = "default"
            $value.withLock { $0 = "settled" }
            try await $value.save()

            let rows = try await defaultDatabase.read { db in
                try Setting.where { $0.key.eq("healed") }.fetchAll(db)
            }
            #expect(rows.count == 1)
            #expect(rows.first?.value == "settled")
        }
    }
}

@MainActor
@Suite("Synced Setting Seed Tests")
struct SyncedSettingSeedTests {
    @Test("Seeds appStorage values, skipping unset keys")
    func seedsFromDefaults() async throws {
        try await withDependencies {
            $0.uuid = .incrementing
            $0.defaultDatabase = try! $0.appDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var defaultDatabase
            let suiteName = "seed-test-\(UUID())"
            let defaults = UserDefaults(suiteName: suiteName)!
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set("22:0-6:0", forKey: SCREEN_OFF_SETTING_KEY)
            defaults.set(true, forKey: BUS_ALERTS_ENABLED_SETTING_KEY)
            // busWindow deliberately unset: an unconfigured key must not seed.

            let now = Date(timeIntervalSince1970: 1000)
            try await defaultDatabase.write { db in
                // UserDefaults isn't Sendable; re-open the suite by name.
                try seedSyncedSettings(
                    from: UserDefaults(suiteName: suiteName)!, now: now, in: db
                )
            }

            let rows = try await defaultDatabase.read { db in
                try Setting.all.fetchAll(db)
            }
            #expect(rows.count == 2)
            #expect(
                rows.first { $0.key == SCREEN_OFF_SETTING_KEY }?.value == "22:0-6:0"
            )
            #expect(
                rows.first { $0.key == BUS_ALERTS_ENABLED_SETTING_KEY }?.value == "true"
            )
            #expect(rows.allSatisfy { $0.lastModified == now })
            #expect(!rows.contains { $0.key == BUS_WINDOW_SETTING_KEY })
        }
    }

    @Test("Never overwrites an existing row")
    func seedRespectsExistingRow() async throws {
        try await withDependencies {
            $0.uuid = .incrementing
            $0.defaultDatabase = try! $0.appDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var defaultDatabase
            @Dependency(\.uuid) var uuid
            let suiteName = "seed-test-\(UUID())"
            let defaults = UserDefaults(suiteName: suiteName)!
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set("9:0-17:0", forKey: SCREEN_OFF_SETTING_KEY)

            try await defaultDatabase.write { db in
                try Setting.insert {
                    Setting(
                        id: Setting.ID(uuid()),
                        key: SCREEN_OFF_SETTING_KEY,
                        value: "synced-from-another-device",
                        lastModified: Date(timeIntervalSince1970: 500)
                    )
                }.execute(db)
                try seedSyncedSettings(
                    from: UserDefaults(suiteName: suiteName)!,
                    now: Date(timeIntervalSince1970: 1000),
                    in: db
                )
            }

            let rows = try await defaultDatabase.read { db in
                try Setting.where { $0.key.eq(SCREEN_OFF_SETTING_KEY) }.fetchAll(db)
            }
            #expect(rows.count == 1)
            #expect(rows.first?.value == "synced-from-another-device")
        }
    }

    @Test("A seeded row is readable and updatable through .syncedSetting")
    func seededRowFlowsIntoSharedKey() async throws {
        try await withDependencies {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 2000))
            $0.defaultDatabase = try! $0.appDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var defaultDatabase
            let suiteName = "seed-test-\(UUID())"
            let defaults = UserDefaults(suiteName: suiteName)!
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set("22:0-6:0", forKey: SCREEN_OFF_SETTING_KEY)

            try await defaultDatabase.write { db in
                try seedSyncedSettings(
                    from: UserDefaults(suiteName: suiteName)!,
                    now: Date(timeIntervalSince1970: 1000),
                    in: db
                )
            }

            @Shared(.syncedSetting(SCREEN_OFF_SETTING_KEY)) var schedule: ScreenOffSchedule?
            #expect(schedule?.rawValue == "22:0-6:0")

            // The seeded row carries the key-derived id, so a save updates it
            // in place instead of adding a second row.
            $schedule.withLock { $0 = .default }
            try await $schedule.save()
            let rows = try await defaultDatabase.read { db in
                try Setting.where { $0.key.eq(SCREEN_OFF_SETTING_KEY) }.fetchAll(db)
            }
            #expect(rows.count == 1)
            #expect(rows.first?.value == ScreenOffSchedule.default.rawValue)
        }
    }
}

/// Polls until `condition` passes; records an issue on timeout. Observation
/// deliveries arrive from the database writer queue, so tests can't assert
/// them synchronously.
private func eventually(
    timeout: Duration = .seconds(5),
    _ condition: @Sendable () -> Bool
) async throws {
    let start = ContinuousClock.now
    while !condition() {
        if ContinuousClock.now - start > timeout {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
