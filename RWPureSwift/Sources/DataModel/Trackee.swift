import Foundation
import SwiftData

@Model
public class Trackee: Comparable, Identifiable, Equatable {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var name: String
    
    @Relationship(deleteRule: .cascade)
    public var reminderTimes: [ReminderTime]
    
    public init(id: UUID, name: String, reminderTimes: [ReminderTime]) {
        self.id = id
        self.name = name
        self.reminderTimes = reminderTimes
    }
    
    public static func < (lhs: Trackee, rhs: Trackee) -> Bool {
        lhs.name < rhs.name
    }
}
