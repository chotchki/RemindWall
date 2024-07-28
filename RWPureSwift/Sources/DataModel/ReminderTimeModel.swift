import Foundation
import SwiftData

@Model
public class ReminderTimeModel: Equatable, Identifiable {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var associatedTag: String?
    
    public var lastScan: Date?
    
    public var reminderTime: ReminderTime
    
    @Relationship(inverse: \Trackee.reminderTimes)
    
    public init() {
        self.id = UUID()
        self.associatedTag = nil
        self.lastScan = nil
        self.reminderTime = ReminderTime(weekDay: 1, hour: 1, minute: 1)
    }
    
    public init(id: UUID, associatedTag: String? = nil, lastScan: Date? = nil, reminderTime: ReminderTime ) {
        self.id = id
        self.associatedTag = associatedTag
        self.lastScan = lastScan
        self.reminderTime = reminderTime
    }
    
    public func isLate(date: Date, calendar: Calendar) -> Bool {
        return reminderTime.inLateWindow(asOf: date, calendar: calendar) && (lastScan == nil || lastScan!.timeIntervalSince(date) > TimeInterval(60*60*6))
    }
    
    public func isScannable(date: Date, calendar: Calendar) -> Bool {
        return reminderTime.inScanWindow(asOf: date, calendar: calendar)
    }
}

///Technique from here: https://stackoverflow.com/a/77775620
extension ReminderTimeModel {
    @MainActor
    public static var preview: ModelContainer {
        let container  = DataSchema.modelContainer
        container.mainContext.insert(ReminderTimeModel())
        return container
    }
}
