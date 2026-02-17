import SwiftUI
import SQLiteData
import Dao
import EditSettings_TopLevel

@main
@MainActor
struct RemindWalliOSApp: App {
    // NB: This is static to avoid interference with Xcode previews, which create this entry
    //     point each time they are run.
    static let store = Store(initialState: .State()) {
        SettingsFeature()
        ._printChanges()
    } withDependencies: {
      if ProcessInfo.processInfo.environment["UITesting"] == "true" {
        $0.defaultFileStorage = .inMemory
      }
    }
    
    init() {
        prepareDependencies {
          $0.defaultDatabase = try! appDatabase()
        }
    }
    
    var body: some Scene {
      WindowGroup {
        if isTesting {
          // NB: Don't run application in tests to avoid interference between the app and the test.
          EmptyView()
        } else {
            SettingsView(store: Self.store)
        }
      }
    }
}
