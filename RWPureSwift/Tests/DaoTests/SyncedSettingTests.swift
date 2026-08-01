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
