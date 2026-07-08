import Dao
import Dependencies
import DependenciesTestSupport
import Foundation
import GRDB
import SQLiteData
import StructuredQueries
import Testing

@MainActor
@Suite("Schema Tests")
struct SchemaTests {
    @Test("Database Seed Sample Data")
    func database_config() throws {
        withDependencies {
            $0.uuid = .incrementing
            $0.defaultDatabase = try! $0.appDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var defaultDatabase
            let _ = try! defaultDatabase.write{ db in
                try! db.seedSampleData()
            }
        }
    }
    
    @Test("Insert and query a setting")
    func insertAndQuerySetting() async throws {
        let fixedDate = Date(timeIntervalSince1970: 1000)
        await withDependencies {
            $0.uuid = .incrementing
            $0.date = .constant(fixedDate)
            $0.defaultDatabase = try! $0.appDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var defaultDatabase
            @Dependency(\.uuid) var uuid
            
            let setting = Setting(
                id: Setting.ID(uuid()),
                key: "testKey",
                value: "testValue",
                lastModified: fixedDate
            )
            
            try! await defaultDatabase.write { db in
                try Setting.insert{setting}.execute(db)
            }
            
            let fetched = try! await defaultDatabase.read { db in
                try Setting.where { $0.key.eq("testKey") }.fetchOne(db)
            }
            
            #expect(fetched != nil)
            #expect(fetched?.key == "testKey")
            #expect(fetched?.value == "testValue")
        }
    }
    
    @Test("INSERT OR REPLACE on trackees does not cascade-delete reminders")
    func insertOrReplaceDoesNotCascadeDelete() async throws {
        await withDependencies {
            $0.uuid = .incrementing
            $0.defaultDatabase = try! $0.appDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var defaultDatabase
            @Dependency(\.uuid) var uuid

            let trackeeId = Trackee.ID(uuid())
            let reminderId = UUID()

            // Insert a trackee and a reminder
            try! await defaultDatabase.write { db in
                try Trackee.insert{Trackee(id: trackeeId, name: "Alice")}.execute(db)
                try db.execute(
                    sql: """
                    INSERT INTO "reminderTimes" ("id", "weekDay", "hour", "minute", "trackeeId")
                    VALUES (?, 1, 9, 0, ?)
                    """,
                    arguments: [reminderId.uuidString, trackeeId.rawValue.uuidString]
                )
            }

            // Verify reminder exists
            let before = try! await defaultDatabase.read { db in
                try ReminderTime.where { $0.trackeeId.eq(trackeeId) }.fetchAll(db)
            }
            #expect(before.count == 1)

            // Simulate what SyncEngine does: INSERT OR REPLACE the same trackee
            try! await defaultDatabase.write { db in
                try db.execute(
                    sql: """
                    INSERT OR REPLACE INTO "trackees" ("id", "name")
                    VALUES (?, ?)
                    """,
                    arguments: [trackeeId.rawValue.uuidString, "Alice"]
                )
            }

            // Verify reminder still exists after INSERT OR REPLACE
            let after = try! await defaultDatabase.read { db in
                try ReminderTime.where { $0.trackeeId.eq(trackeeId) }.fetchAll(db)
            }
            #expect(after.count == 1, "Reminder was cascade-deleted by INSERT OR REPLACE on trackees")
        }
    }

    @Test("Insert and query a MonitoredStop")
    func insertAndQueryMonitoredStop() async throws {
        await withDependencies {
            $0.uuid = .incrementing
            $0.defaultDatabase = try! $0.appDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var defaultDatabase
            @Dependency(\.uuid) var uuid

            let stop = MonitoredStop(
                id: MonitoredStop.ID(uuid()),
                label: "School bus",
                stopId: "1_75403",
                routeId: "1_100224",
                routeShortName: "12",
                sortOrder: 0
            )

            try! await defaultDatabase.write { db in
                try MonitoredStop.insert { stop }.execute(db)
            }

            let fetched = try! await defaultDatabase.read { db in
                try MonitoredStop.where { $0.stopId.eq("1_75403") }.fetchOne(db)
            }

            #expect(fetched != nil)
            #expect(fetched?.label == "School bus")
            #expect(fetched?.routeId == "1_100224")
            #expect(fetched?.routeShortName == "12")
            #expect(fetched?.sortOrder == 0)
        }
    }

    @Test("MonitoredStop ordering by sortOrder")
    func monitoredStopOrdering() async throws {
        await withDependencies {
            $0.uuid = .incrementing
            $0.defaultDatabase = try! $0.appDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var defaultDatabase
            @Dependency(\.uuid) var uuid

            try! await defaultDatabase.write { db in
                try MonitoredStop.insert {
                    MonitoredStop(
                        id: MonitoredStop.ID(uuid()),
                        label: "Second", stopId: "1_2", routeId: "1_b",
                        routeShortName: "B", sortOrder: 1
                    )
                    MonitoredStop(
                        id: MonitoredStop.ID(uuid()),
                        label: "First", stopId: "1_1", routeId: "1_a",
                        routeShortName: "A", sortOrder: 0
                    )
                }.execute(db)
            }

            let ordered = try! await defaultDatabase.read { db in
                try MonitoredStop.all.order(by: \.sortOrder).fetchAll(db)
            }

            #expect(ordered.map(\.label) == ["First", "Second"])
        }
    }

    @Test("INSERT OR REPLACE on monitoredStops preserves siblings")
    func monitoredStopReplaceDoesNotDropOthers() async throws {
        await withDependencies {
            $0.uuid = .incrementing
            $0.defaultDatabase = try! $0.appDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var defaultDatabase
            @Dependency(\.uuid) var uuid

            let kept = MonitoredStop.ID(uuid())
            let replaced = MonitoredStop.ID(uuid())

            try! await defaultDatabase.write { db in
                try MonitoredStop.insert {
                    MonitoredStop(
                        id: kept,
                        label: "Keep", stopId: "1_k", routeId: "1_a",
                        routeShortName: "A", sortOrder: 0
                    )
                    MonitoredStop(
                        id: replaced,
                        label: "Original", stopId: "1_r", routeId: "1_b",
                        routeShortName: "B", sortOrder: 1
                    )
                }.execute(db)
            }

            // Simulate what SyncEngine does: INSERT OR REPLACE the same row id.
            try! await defaultDatabase.write { db in
                try db.execute(
                    sql: """
                    INSERT OR REPLACE INTO "monitoredStops"
                      ("id", "label", "stopId", "routeId", "routeShortName", "sortOrder")
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        replaced.rawValue.uuidString,
                        "Updated", "1_r", "1_b", "B", 1
                    ]
                )
            }

            let all = try! await defaultDatabase.read { db in
                try MonitoredStop.all.order(by: \.sortOrder).fetchAll(db)
            }
            #expect(all.count == 2)
            #expect(all.map(\.label) == ["Keep", "Updated"])
        }
    }

    @Test("Trackee defaults to remindersEnabled and can be soft-disabled")
    func trackeeRemindersEnabledDefaultAndToggle() async throws {
        await withDependencies {
            $0.uuid = .incrementing
            $0.defaultDatabase = try! $0.appDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var defaultDatabase
            @Dependency(\.uuid) var uuid

            let trackeeId = Trackee.ID(uuid())

            // A trackee inserted without naming the flag comes back enabled.
            try! await defaultDatabase.write { db in
                try Trackee.insert { Trackee(id: trackeeId, name: "Alice") }.execute(db)
            }
            let inserted = try! await defaultDatabase.read { db in
                try Trackee.find(trackeeId).fetchOne(db)
            }
            #expect(inserted?.remindersEnabled == true)

            // Soft-disable persists.
            try! await defaultDatabase.write { db in
                try Trackee.find(trackeeId)
                    .update { $0.remindersEnabled = false }
                    .execute(db)
            }
            let disabled = try! await defaultDatabase.read { db in
                try Trackee.find(trackeeId).fetchOne(db)
            }
            #expect(disabled?.remindersEnabled == false)
        }
    }

    @Test("Setting with same key uses last modified for conflict resolution")
    func settingLastModifiedConflict() async throws {
        await withDependencies {
            $0.uuid = .incrementing
            $0.defaultDatabase = try! $0.appDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var defaultDatabase
            @Dependency(\.uuid) var uuid
            
            let earlier = Date(timeIntervalSince1970: 1000)
            let later = Date(timeIntervalSince1970: 2000)
            
            let setting1 = Setting(
                id: Setting.ID(uuid()),
                key: "albumId",
                value: "album-old",
                lastModified: earlier
            )
            
            try! await defaultDatabase.write { db in
                try Setting.insert{setting1}.execute(db)
            }
            
            // Fetch and verify first insert
            let first = try! await defaultDatabase.read { db in
                try Setting.where { $0.key.eq("albumId") }.fetchOne(db)
            }
            #expect(first?.value == "album-old")
            
            // Update with newer timestamp
            try! await defaultDatabase.write { db in
                try Setting
                    .where { $0.key.eq("albumId") }
                    .update {
                        $0.value = "album-new"
                        $0.lastModified = later
                    }
                    .execute(db)
            }
            
            let updated = try! await defaultDatabase.read { db in
                try Setting.where { $0.key.eq("albumId") }.fetchOne(db)
            }
            #expect(updated?.value == "album-new")
            #expect(updated?.lastModified == later)
        }
    }
}

