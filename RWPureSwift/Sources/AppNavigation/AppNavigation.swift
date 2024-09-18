import AppModel
import CheckPermissions
import Dashboard
import DataModel
import EditSettings
import PhotosUI
@preconcurrency import SwiftData
import SwiftUI
import Utility

public struct AppNavigation: View {
    @Environment(\.modelContext) var modelContext
    
    @Query(filter: #Predicate<Settings> { s in
        s.id == "0D8698C8-B58A-42F3-AB32-AAB565C074A2"
    }) var settingsQuery: [Settings]
    
    public init() {}
    
    @State var state = AppState.checkPermissions
    
    public var body: some View {
        NavigationStack {
            switch state {
            case .checkPermissions:
                CheckPermissionsView(state: $state)
            case .editSettings:
                EditSettingsView(state: $state)
            case .dashboard:
                DashboardView(state: $state)
            }
        }
        .environment(settingsQuery.first!)
    }
}

#Preview {
    let container = Settings.preview
    
    return AppNavigation().modelContainer(container)
}


