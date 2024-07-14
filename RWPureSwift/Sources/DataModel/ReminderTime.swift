import Foundation
import SwiftData

@Model
public class ReminderTime: Equatable, Identifiable {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var associatedTag: [UInt8]?
    
    public var lastScan: Date?
    
    public var weekDay: Int
    public var hour: Int
    public var minute: Int
    
    public init() {
        self.id = UUID()
        self.associatedTag = nil
        self.lastScan = nil
        self.weekDay = 1
        self.hour = 1
        self.minute = 1
    }
    
    public init(id: UUID, associatedTag: [UInt8]? = nil, lastScan: Date? = nil, weekDay: Int, hour: Int, minute: Int) {
        self.id = id
        self.associatedTag = associatedTag
        self.lastScan = lastScan
        self.weekDay = weekDay
        self.hour = hour
        self.minute = minute
    }
}

///Technique from here: https://stackoverflow.com/a/77775620
extension ReminderTime {
    @MainActor
    public static var preview: ModelContainer {
        let container  = DataSchema.previewContainer
        container.mainContext.insert(ReminderTime())
        return container
    }
}
