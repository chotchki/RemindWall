import EventKit
import PhotosUI
import SwiftUI
import SwiftData

import AppNavigation
import DataModel
import Utility

@main
@MainActor
struct RemindWallApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Settings.self, Trackee.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            // Make sure the persistent store is empty. If it's not, return the non-empty container.
            var itemFetchDescriptor = FetchDescriptor<Settings>()
            itemFetchDescriptor.fetchLimit = 1
            
            guard try container.mainContext.fetch(itemFetchDescriptor).count == 0 else { return container }
            
            // This code will only run if the persistent store is empty.
            container.mainContext.insert(Settings())

            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
        
    @State private var globalEventStore = GlobalEventStore.shared

    var body: some Scene {
        WindowGroup {
            AppNavigation()
        }
        .modelContainer(sharedModelContainer)
    }
}

