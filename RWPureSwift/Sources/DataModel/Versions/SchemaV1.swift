import Foundation
@preconcurrency import SwiftData

public enum SchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [ReminderTimeModel.self, Settings.self, Trackee.self]
    }
    
    @Model
    public class ReminderTimeModel: Equatable {
        public var trackeeId: UUID = UUID()
        
        public var associatedTag: String?
        
        public var lastScan: Date?
        
        //Range 1 = Sun to 7 = Sat
        public var weekDay: Int = 1
        public var hour: Int = 1
        public var minute: Int = 1
        
        public var reminderTime: ReminderTime {
            ReminderTime(weekDay: weekDay, hour: hour, minute: minute)
        }
            
        public init() {
            self.associatedTag = nil
            self.lastScan = nil
        }
        
        public init(trackeeId: UUID = UUID(), associatedTag: String? = nil, lastScan: Date? = nil, weekDay: Int = 1, hour: Int = 1, minute: Int = 1) {
            self.trackeeId = trackeeId
            self.associatedTag = associatedTag
            self.lastScan = lastScan
            self.weekDay = weekDay
            self.hour = hour
            self.minute = minute
        }
        
        public func isLate(date: Date, calendar: Calendar) -> Bool {
            return reminderTime.inLateWindow(asOf: date, calendar: calendar) && (lastScan == nil || lastScan!.timeIntervalSince(date) > TimeInterval(60*60*6))
        }
        
        public func isScannable(date: Date, calendar: Calendar) -> Bool {
            return reminderTime.inScanWindow(asOf: date, calendar: calendar)
        }
    }

    @Model
    public class Settings: Equatable {
        public var id: UUID = UUID(uuidString: "0D8698C8-B58A-42F3-AB32-AAB565C074A2")!
        public var selectedAlbumId: String?
        public var selectedCalendarId: String?

        public init(
            selectedAlbumId: String? = nil,
            selectedCalendarId: String? = nil
        ) {
            self.selectedAlbumId = selectedAlbumId
            self.selectedCalendarId = selectedCalendarId
        }
    }
    
    @Model
    public class Trackee {
        public var id: UUID = UUID()
        public var name: String = "Unknown"
        
        public init(id: UUID = UUID(), name: String) {
            self.id = id
            self.name = name
        }
    }
}
