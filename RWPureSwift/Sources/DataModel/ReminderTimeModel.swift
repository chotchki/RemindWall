import Foundation
import SwiftData

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

///Technique from here: https://stackoverflow.com/a/77775620
extension ReminderTimeModel {
    @MainActor
    public static var preview: ModelContainer {
        let container  = DataSchema.modelContainer
        container.mainContext.insert(ReminderTimeModel())
        return container
    }
}
