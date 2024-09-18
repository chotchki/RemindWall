import AppModel
import DataModel
import PhotosUI
import SwiftData
import SwiftUI
import Utility

@MainActor
public struct EditSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(Settings.self) private var settings
    
    private static func baseFetchOptions() -> PHFetchOptions {
        // From: https://stackoverflow.com/a/49495326/160208
        // We don't sort because we'll be shuffling anyway
        let pfo = PHFetchOptions()
        pfo.includeHiddenAssets = false
        return pfo
    }
    
    let availibleAlbums = PHFetchResultAssetCollection(fetchResult: PHAssetCollection.fetchAssetCollections(
        with: PHAssetCollectionType.album,
        subtype: PHAssetCollectionSubtype.any,
        options: baseFetchOptions()))
    
    let availibleCalendars = GlobalEventStore.shared.getCalendars()

    @Binding var state: AppState
    
    public init(state: Binding<AppState>) {
        self._state = state
    }
    
    public var body: some View {
        NavigationStack {
            Form{
                @Bindable var settings = settings
                Section {
                    Picker("Albums", selection: $settings.selectedAlbumId){
                        Text("Select Album").tag(nil as String?)
                        ForEach(availibleAlbums, id: \.localIdentifier) { album in
                            Text(album.localizedTitle ?? "Unknown Album").tag(Optional(album.localIdentifier))
                        }
                    }
                } header: {
                    Text("Select Album for Slideshow")
                }
                
                Section {
                    Picker("Calendars", selection: $settings.selectedCalendarId){
                        Text("Select Calendar").tag(nil as String?)
                        ForEach(
                            availibleCalendars,
                            id: \.calendarIdentifier
                        ) { calendar in
                            Text(calendar.title).tag(Optional(calendar.calendarIdentifier))
                        }
                    }
                } header: {
                    Text("Select Calendar for Event Reminders")
                }
                
                Section {
                    TrackeesView()
                } header: {
                    Text("Trackees")
                }
                
                Section {
                    Button {
                        state = .dashboard
                    } label: {
                        Text("Start Slideshow")
                    }
                    
                    #if targetEnvironment(macCatalyst)
                    Button {
                        exit(0)
                    } label: {
                        Text("Quit Application")
                    }
                    #endif
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var state = AppState.editSettings
    let container = Settings.preview

    return NavigationStack {
        EditSettingsView(state: $state)
    }.modelContainer(container)
}
