import Dao
import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
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
}

