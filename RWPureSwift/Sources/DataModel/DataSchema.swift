import Foundation
import SwiftData

@MainActor
public struct DataSchema {
    public static let modelContainer: ModelContainer = {
        let schema = Schema([ReminderTimeModel.self, Settings.self, Trackee.self])
        
        let mC : ModelContainer
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            mC = try! ModelContainer(for: schema, configurations: .init(isStoredInMemoryOnly: true))
        } else {
            //Once I figure out production, I'll need to change this
            mC = try! ModelContainer(for: schema, configurations: .init(isStoredInMemoryOnly: false))
        }
        
        //Ensure there is a Settings row always present
        var itemFetchDescriptor = FetchDescriptor<Settings>()
        itemFetchDescriptor.fetchLimit = 1
        
        guard try! mC.mainContext.fetch(itemFetchDescriptor).count == 0 else { return mC }
        
        mC.mainContext.insert(Settings())
        
        return mC
    }()
}
