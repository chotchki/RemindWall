import Foundation
import SwiftData

@Model
public class ReminderTime: Equatable, Identifiable {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var associatedTag: [UInt8]?
    
    public var lastScan: Date?
    
    public var components: DateComponents
    
    public init(){
        self.id = UUID()
        self.components = DateComponents()
    }
    
    public init(id: UUID, associatedTag: [UInt8]? = nil, lastScan: Date? = nil, components: DateComponents) {
        self.id = id
        self.associatedTag = associatedTag
        self.lastScan = lastScan
        self.components = components
    }
}
