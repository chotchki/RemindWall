import EventKit
import SwiftUI
import SwiftData

import AppNavigation
import DataModel
import Utility

@main
@MainActor
struct RemindWalliOSApp: App {
    @State private var globalEventStore = GlobalEventStore.shared
    
    var body: some Scene {
        WindowGroup {
            AppNavigation()
        }
        .modelContainer(DataSchema.modelContainer)
    }
}

