import SwiftUI
import SQLiteData
import Dao
import AppNavigation
import ComposableArchitecture

@main
@MainActor
struct RemindWallApp: App {
    private static let isUITesting = ProcessInfo.processInfo.environment["UITesting"] == "true"

    // NB: This is static to avoid interference with Xcode previews, which create this entry
    //     point each time they are run.
    static let store: StoreOf<AppNavigationFeature> = {
        // Clear persisted UserDefaults (used by @Shared(.appStorage)) for a clean UI test state
        if isUITesting, let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
        }
        return Store(initialState: AppNavigationFeature.State()) {
            AppNavigationFeature()
            ._printChanges()
        } withDependencies: {
            if isUITesting {
                $0.defaultFileStorage = .inMemory
            }
        }
    }()
    
    init() {
        prepareDependencies {
            $0.defaultDatabase = try! $0.appDatabase()
            if !isTesting && !Self.isUITesting {
                $0.defaultSyncEngine = try! $0.appSyncEngine(for: $0.defaultDatabase)
            }
        }
    }
    
    var body: some Scene {
      WindowGroup {
        if ProcessInfo.processInfo.environment.keys.contains("XCTestBundlePath") {
          // NB: Don't run application in unit tests to avoid interference between the app and the test.
          //     UI tests need the real UI, so only check for XCTestBundlePath (set in-process for unit tests only).
          EmptyView()
        } else {
            AppNavigationView(store: Self.store)
        }
      }
    }
}
