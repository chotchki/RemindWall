import Dao
import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import StructuredQueries
import Testing

@MainActor
@Suite("Schema Tests")
struct SchemaTests {
    @Test("Database Seed Sample Data")
    func database_config() async throws {
        await withDependencies {
            $0.uuid = .incrementing
            $0.defaultDatabase = try! $0.appDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var defaultDatabase
            try! await defaultDatabase.write{ db in
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
                try Setting.insert(setting).execute(db)
            }
            
            let fetched = try! await defaultDatabase.read { db in
                try Setting.where { $0.key.eq("testKey") }.fetchOne(db)
            }
            
            #expect(fetched != nil)
            #expect(fetched?.key == "testKey")
            #expect(fetched?.value == "testValue")
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
                try Setting.insert(setting1).execute(db)
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

