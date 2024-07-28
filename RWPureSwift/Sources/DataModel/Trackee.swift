import Foundation
import SwiftData

@Model
public class Trackee: Comparable, Identifiable, Equatable {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var name: String
    
    @Relationship(deleteRule: .cascade)
    public var reminderTimes: [ReminderTimeModel]
    
    public init(id: UUID, name: String, reminderTimes: [ReminderTimeModel]) {
        self.id = id
        self.name = name
        self.reminderTimes = reminderTimes
    }
    
    public static func < (lhs: Trackee, rhs: Trackee) -> Bool {
        lhs.name < rhs.name
    }
}

///Technique from here: https://stackoverflow.com/a/77775620
extension Trackee {
    @MainActor
    public static var preview: ModelContainer {
        let container  = DataSchema.modelContainer
        container.mainContext.insert(Trackee(id: UUID(), name: "Bob", reminderTimes: []))
        container.mainContext.insert(Trackee(id: UUID(), name: "Sue", reminderTimes: []))
        
        return container
    }
}
