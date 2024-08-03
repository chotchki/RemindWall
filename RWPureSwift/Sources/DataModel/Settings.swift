import Foundation
import SwiftData

public typealias Settings = SchemaV2.Settings

///Technique from here: https://stackoverflow.com/a/77775620
extension Settings {
    @MainActor
    public static var preview: ModelContainer {
        let container  = DataSchema.modelContainer
        container.mainContext.insert(Settings())
        return container
    }
}
