// From https://swiftpackageindex.com/pointfreeco/sqlite-data/main/documentation/sqlitedata/preparingdatabase
// From https://github.com/pointfreeco/sqlite-data/blob/main/Examples/Reminders/Schema.swift
import AppTypes
import Dependencies
import Foundation
import IssueReporting
import OSLog
import SQLiteData
import Tagged

@Table
public nonisolated struct Trackee: Equatable, Identifiable, Sendable {
    public typealias ID = Tagged<Self, UUID>
    
    public let id: ID
    public var name: String = ""
    
    public init(id: ID, name: String) {
        self.id = id
        self.name = name
    }
    
    //public static let all = Self.order(by: \.name)
}

@Table
public nonisolated struct ReminderTime: Equatable, Identifiable, Sendable {
    public typealias ID = Tagged<Self, UUID>
    
    public let id: ID
    public var weekDay: Int = 1
    public var hour: Int = 1
    public var minute: Int = 1
    public var associatedTag: TagSerial?
    public var lastScan: Date?
    public var trackeeId: Trackee.ID
    
    public var reminderPart: ReminderPart {
        ReminderPart(weekDay: DaysOfWeek(rawValue: weekDay)!, hour: hour, minute: minute)
    }
    
    public func isLate(date: Date, calendar: Calendar) -> Bool {
        let inLateWindow = reminderPart.inLateWindow(asOf: date, calendar: calendar)
        let timeSinceLastScan = Swift.abs(lastScan?.timeIntervalSince(date) ?? TimeInterval.greatestFiniteMagnitude)
        let lastScanAged = timeSinceLastScan > TimeInterval(60*60*6)
        return inLateWindow && lastScanAged
    }
    
    public func isScannable(date: Date, calendar: Calendar) -> Bool {
        return reminderPart.inScanWindow(asOf: date, calendar: calendar)
    }
}

extension ReminderTime.Draft: Equatable, Sendable {
    
}



extension DependencyValues {
    public mutating func appDatabase() throws -> any DatabaseWriter {
        @Dependency(\.context) var context
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.prepareDatabase { db in
            db.add(function: $uuid)
            //try db.attachMetadatabase()
#if DEBUG
            db.trace(options: .profile) {
                switch context {
                case .live:
                    logger.debug("\($0.expandedDescription)")
                case .preview:
                    print("\($0.expandedDescription)")
                case .test:
                    break
                }
            }
#endif
        }
        let database = try SQLiteData.defaultDatabase(configuration: configuration)
        logger.debug(
      """
      App database:
      open "\(database.path)"
      """
        )
        
        var migrator = DatabaseMigrator()
#if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
#endif
        migrator.registerMigration("Create initial tables") { db in
            try #sql(
            """
            CREATE TABLE "trackees" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "name" TEXT NOT NULL
            )
            """
            )
            .execute(db)
            
            try #sql(
            """
            CREATE TABLE "reminderTimes" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "weekDay" INT NOT NULL,
              "hour" INT NOT NULL,
              "minute" INT NOT NULL,
              "associatedTag" TEXT NULL,
              "lastScan" TEXT NULL,
              "trackeeId" TEXT NOT NULL REFERENCES "trackees"("id") ON DELETE CASCADE
            )
            """
            )
            .execute(db)
        }
        
        try migrator.migrate(database)
        
        try database.write { db in
            if context != .live {
                let _ = try db.seedSampleData()
            }
        }
        
        return database
    }
}

private let logger = Logger(subsystem: "Reminders", category: "Database")

#if DEBUG
extension Database {
    public func seedSampleData() throws -> Self {
        @Dependency(\.date.now) var now
        @Dependency(\.uuid) var uuid
        
        var trackeeIDs: [Trackee.ID] = []
        for _ in 0...5 {
            trackeeIDs.append(Trackee.ID(uuid()))
        }
        
        try seed {
            Trackee(
                id: trackeeIDs[0],
                name: "Alice"
            )
            Trackee(
                id: trackeeIDs[1],
                name: "Bob"
            )
        }
        
        return self
    }
}
#endif

@DatabaseFunction
nonisolated var uuid: UUID {
  @Dependency(\.uuid) var uuid
  return uuid()
}
