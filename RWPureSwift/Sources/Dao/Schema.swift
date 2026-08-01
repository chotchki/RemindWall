// From https://swiftpackageindex.com/pointfreeco/sqlite-data/main/documentation/sqlitedata/preparingdatabase
// From https://github.com/pointfreeco/sqlite-data/blob/main/Examples/Reminders/Schema.swift
import AppTypes
import Dependencies
import Foundation
import IssueReporting
import OSLog
import Sharing
import SQLiteData
import Tagged

@Table
public nonisolated struct Trackee: Equatable, Identifiable, Sendable {
    public typealias ID = Tagged<Self, UUID>
    
    public let id: ID
    public var name: String = ""
    /// Soft-disable: when false the trackee is skipped by the dashboard late-alert
    /// surface (no "X is late" nag). The tag-scan path is deliberately NOT gated —
    /// a real tap still credits the dose — so this is "remindersEnabled", not "isActive".
    public var remindersEnabled: Bool = true

    public init(id: ID, name: String, remindersEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.remindersEnabled = remindersEnabled
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



@Table
public nonisolated struct Setting: Equatable, Identifiable, Sendable {
    public typealias ID = Tagged<Self, UUID>

    public let id: ID
    public var key: String
    public var value: String
    public var lastModified: Date

    public init(id: ID, key: String, value: String, lastModified: Date) {
        self.id = id
        self.key = key
        self.value = value
        self.lastModified = lastModified
    }
}

@Table
public nonisolated struct MonitoredStop: Equatable, Identifiable, Sendable {
    public typealias ID = Tagged<Self, UUID>

    public let id: ID
    public var label: String
    public var stopId: String
    public var routeId: String
    public var routeShortName: String
    public var sortOrder: Int

    public init(
        id: ID,
        label: String,
        stopId: String,
        routeId: String,
        routeShortName: String,
        sortOrder: Int
    ) {
        self.id = id
        self.label = label
        self.stopId = stopId
        self.routeId = routeId
        self.routeShortName = routeShortName
        self.sortOrder = sortOrder
    }
}

extension MonitoredStop.Draft: Equatable, Sendable {}

@Table
public nonisolated struct MonitoredRoute: Equatable, Identifiable, Sendable {
    public typealias ID = Tagged<Self, UUID>

    public let id: ID
    public var label: String
    public var destinationLatitude: Double
    public var destinationLongitude: Double
    public var destinationName: String
    /// The commute's baseline; TR1.5 styles the card late when the live ETA
    /// exceeds this plus the threshold.
    public var normalMinutes: Int
    public var sortOrder: Int

    public init(
        id: ID,
        label: String,
        destinationLatitude: Double,
        destinationLongitude: Double,
        destinationName: String,
        normalMinutes: Int,
        sortOrder: Int
    ) {
        self.id = id
        self.label = label
        self.destinationLatitude = destinationLatitude
        self.destinationLongitude = destinationLongitude
        self.destinationName = destinationName
        self.normalMinutes = normalMinutes
        self.sortOrder = sortOrder
    }
}

extension MonitoredRoute.Draft: Equatable, Sendable {}

extension DependencyValues {
    public mutating func appDatabase() throws -> any DatabaseWriter {
        @Dependency(\.context) var context
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let isUITesting = ProcessInfo.processInfo.environment["UITesting"] == "true"
        let needsSync = context == .live && !isUITesting
        configuration.prepareDatabase { db in
            db.add(function: $uuid)
            if needsSync {
                try db.attachMetadatabase()
            }
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
        let database: any DatabaseWriter
        if context != .live || isUITesting {
            database = try DatabaseQueue(configuration: configuration)
            logger.debug("App database: in-memory")
        } else {
            let onDisk = try SQLiteData.defaultDatabase(configuration: configuration)
            logger.debug(
          """
          App database:
          open "\(onDisk.path)"
          """
            )
            database = onDisk
        }
        
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
        
        migrator.registerMigration("Remove cascade delete from reminderTimes") { db in
            try db.execute(sql: """
                CREATE TABLE "reminderTimes_new" (
                  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                  "weekDay" INT NOT NULL,
                  "hour" INT NOT NULL,
                  "minute" INT NOT NULL,
                  "associatedTag" TEXT NULL,
                  "lastScan" TEXT NULL,
                  "trackeeId" TEXT NOT NULL
                )
                """)
            try db.execute(sql: """
                INSERT INTO "reminderTimes_new" SELECT * FROM "reminderTimes"
                """)
            try db.execute(sql: """
                DROP TABLE "reminderTimes"
                """)
            try db.execute(sql: """
                ALTER TABLE "reminderTimes_new" RENAME TO "reminderTimes"
                """)
        }
        
        migrator.registerMigration("Create settings table") { db in
            try #sql(
            """
            CREATE TABLE "settings" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "key" TEXT NOT NULL,
              "value" TEXT NOT NULL,
              "lastModified" TEXT NOT NULL
            )
            """
            )
            .execute(db)
        }

        migrator.registerMigration("Create monitoredStops table") { db in
            try #sql(
            """
            CREATE TABLE "monitoredStops" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "label" TEXT NOT NULL,
              "stopId" TEXT NOT NULL,
              "routeId" TEXT NOT NULL,
              "routeShortName" TEXT NOT NULL,
              "sortOrder" INTEGER NOT NULL DEFAULT 0
            )
            """
            )
            .execute(db)
        }

        migrator.registerMigration("Add remindersEnabled to trackees") { db in
            try #sql(
            """
            ALTER TABLE "trackees" ADD COLUMN "remindersEnabled" INTEGER NOT NULL DEFAULT 1
            """
            )
            .execute(db)
        }

        // Registered after remindersEnabled deliberately: the live kiosk DB
        // has everything above applied - new migrations only ever APPEND.
        migrator.registerMigration("Create monitoredRoutes table") { db in
            try #sql(
            """
            CREATE TABLE "monitoredRoutes" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "label" TEXT NOT NULL,
              "destinationLatitude" REAL NOT NULL,
              "destinationLongitude" REAL NOT NULL,
              "destinationName" TEXT NOT NULL,
              "normalMinutes" INTEGER NOT NULL DEFAULT 0,
              "sortOrder" INTEGER NOT NULL DEFAULT 0
            )
            """
            )
            .execute(db)
        }

        try migrator.migrate(database)
        
        try database.write { db in
            if context != .live || isUITesting {
                #if DEBUG
                let _ = try db.seedSampleData()
                #endif
            } else {
                // One-time migration of appStorage settings into the synced
                // table; no-op once rows exist (locally or via CloudKit).
                @Dependency(\.defaultAppStorage) var defaults
                @Dependency(\.date.now) var now
                try seedSyncedSettings(from: defaults, now: now, in: db)
            }
        }
        
        return database
    }

    public mutating func appSyncEngine(for database: any DatabaseWriter) throws -> SyncEngine {
        try SyncEngine(
            for: database,
            tables: Trackee.self, ReminderTime.self, Setting.self,
            MonitoredStop.self, MonitoredRoute.self
        )
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
