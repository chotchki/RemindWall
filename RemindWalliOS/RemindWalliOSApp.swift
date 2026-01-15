import EventKit
import SwiftUI
import SQLiteData

import AppNavigation
import Dao
import DataModel
import Utility

@main
@MainActor
struct RemindWalliOSApp: App {
    init() {
        prepareDependencies {
          $0.defaultDatabase = try! appDatabase()
        }
    }
    
    @State private var globalEventStore = GlobalEventStore.shared
    
    var body: some Scene {
        WindowGroup {
            AppNavigation()
        }
        .modelContainer(DataSchema.modelContainer)
    }
}

