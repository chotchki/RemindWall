import Foundation
import SwiftData

public typealias Trackee = SchemaV2.Trackee

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
