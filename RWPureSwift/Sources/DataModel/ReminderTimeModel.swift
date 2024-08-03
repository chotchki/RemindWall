import Foundation
import SwiftData

public typealias ReminderTimeModel = SchemaV2.ReminderTimeModel

///Technique from here: https://stackoverflow.com/a/77775620
extension ReminderTimeModel {
    @MainActor
    public static var preview: ModelContainer {
        let container  = DataSchema.modelContainer
        container.mainContext.insert(ReminderTimeModel())
        return container
    }
}
