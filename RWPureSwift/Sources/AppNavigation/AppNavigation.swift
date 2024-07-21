import CheckPermissions
import Dashboard
import DataModel
import EditSettings
import SwiftData
import SwiftUI

public struct AppNavigation: View {
    @Environment(\.modelContext) var modelContext
    
    @Query(filter: #Predicate<Settings> { s in
        s.id == 1
    }) var settingsQuery: [Settings]
    
    public init() {}
    
    @State var state = AppState.checkPermissions
    
    public var body: some View {
        NavigationStack {
            switch state {
            case .checkPermissions:
                CheckPermissionsView(state: $state)
            case .editSettings:
                EditSettingsView(settings: Bindable(settingsQuery.first!), state: $state)
            case .dashboard:
                DashboardView(settings: Bindable(settingsQuery.first!), state: $state)
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
