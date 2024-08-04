import CoreData
import Foundation
import SwiftData

@MainActor
public struct DataSchema {
    public static let modelContainer: ModelContainer = {
        let schema = Schema([ReminderTimeModel.self, Settings.self, Trackee.self])
        
        let modelConfig = if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: true, groupContainer: .automatic, cloudKitDatabase: .private("iCloud.com.remindwall.tracker"))
        } else {
            //Once I figure out production, I'll need to change this
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, allowsSave: true, groupContainer: .automatic, cloudKitDatabase: .private("iCloud.com.remindwall.tracker"))
        }
        
        let mC = try! ModelContainer(for: schema, migrationPlan: MigrationPlan.self, configurations: modelConfig)
            
        //Ensure there is a Settings row always present
        var itemFetchDescriptor = FetchDescriptor<Settings>()
        itemFetchDescriptor.fetchLimit = 1
            
        guard try! mC.mainContext.fetch(itemFetchDescriptor).count == 0 else { return mC }
            
        mC.mainContext.insert(Settings())
            
        return mC
    }()
}

public enum MigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }
    
    public static var stages: [MigrationStage] {
        [migrateV1toV2]
    }
    
    public static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self,
        willMigrate: { context in
            let settingss = try context.fetch(FetchDescriptor<SchemaV1.Settings>())
            
            //Wiping out old settings since they were never public
            for s in settingss {
                context.delete(s)
            }
        }, didMigrate: nil
    )
}
