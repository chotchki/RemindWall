import Foundation
import SwiftData

public struct DataSchema {
    @MainActor
    public static let schema: Schema = Schema([ReminderTimeModel.self, Settings.self, Trackee.self])
    
    @MainActor
    public static var previewContainer: ModelContainer {
        return try! ModelContainer(for: schema, configurations: .init(isStoredInMemoryOnly: true))
    }
}
