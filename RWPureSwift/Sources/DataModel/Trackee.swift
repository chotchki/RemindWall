import Foundation
import SwiftData

@Model
public class Trackee {
    public var id: UUID = UUID()
    public var name: String = "Unknown"
    
    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

///Technique from here: https://stackoverflow.com/a/77775620
extension Trackee {
    @MainActor
    public static var preview: ModelContainer {
        let container  = DataSchema.modelContainer
        container.mainContext.insert(Trackee(name: "Bob"))
        container.mainContext.insert(Trackee(name: "Sue"))
        
        return container
    }
}
