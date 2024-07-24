import CheckPermissions
import Dashboard
import DataModel
import EditSettings
import PhotosUI
import SwiftData
import SwiftUI
import Utility

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
                EditSettingsView(state: $state)
            case .dashboard:
                DashboardView(state: $state)
            }
        }
        .environment(settingsQuery.first!)
        .environment(\.imageManager, PHCachingImageManager())
    }
}

#Preview {
    let container = Settings.preview
    
    return AppNavigation().modelContainer(container)
}
