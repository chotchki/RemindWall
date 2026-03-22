import SwiftUI
import SQLiteData
import Dao
import AppNavigation
import ComposableArchitecture

@main
@MainActor
struct RemindWalliOSApp: App {
    // NB: This is static to avoid interference with Xcode previews, which create this entry
    //     point each time they are run.
    static let store = Store(initialState: AppNavigationFeature.State()) {
        AppNavigationFeature()
        ._printChanges()
    } withDependencies: {
      if ProcessInfo.processInfo.environment["UITesting"] == "true" {
        $0.defaultFileStorage = .inMemory
        print("In UI Tests")
      }
    }
    
    init() {
        prepareDependencies {
          $0.defaultDatabase = try! $0.appDatabase()
        }
    }
    
    var body: some Scene {
      WindowGroup {
        if isTesting {
          // NB: Don't run application in tests to avoid interference between the app and the test.
          EmptyView()
        } else {
            AppNavigationView(store: Self.store)
        }
      }
    }
}
