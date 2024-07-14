import CheckPermissions
import DataModel
import EditSettings
import SwiftData
import SwiftUI

public struct AppNavigation: View {
    @Environment(\.modelContext) var modelContext
    
    @Query(filter: #Predicate<Settings> { s in
        s.id == 1
    }) var settingsQuery: [Settings]
    
    @State var isSetup = false
    
    public init() {}
    
    enum AppState {
        case checkPermissions
        case editSettings
    }
    
    @State var state = AppState.checkPermissions
    
    public var body: some View {
        NavigationStack {
            if !isSetup {
                CheckPermissionsView(isSetup: $isSetup)
            } else {
                EditSettingsView(settings: Bindable(settingsQuery.first!))
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Settings.self, configurations: config)

    @State var settings = Settings()
    return AppNavigation().modelContainer(container)
}
