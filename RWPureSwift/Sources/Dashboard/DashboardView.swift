import AppModel
import EventKit
import DataModel
import Slideshow
import SwiftData
import SwiftUI
import Utility
#if canImport(TagScan)
import TagScan
#endif

public struct DashboardView: View {
    @Environment(Settings.self) private var settings
    @Binding var state: AppState
    
    @State private var currentEvent: EKEvent?
    @State private var nextEvent: EKEvent?
    
    public init(state: Binding<AppState>) {
        self._state = state
    }
    
    public var body: some View {
        ZStack {
            @Bindable var settings = settings
            SlideshowView(state: $state, selectedAlbumId: $settings.selectedAlbumId)
            VStack(alignment: .leading){
                if let c = currentEvent {
                    NowView(currentEvent: c).transition(.slide)
                }
                Spacer()
                if let n = nextEvent {
                    UpNextView(nextEvent: n).transition(.slide)
                }
            }
            AlertLoaderView().onTapGesture {
                state = .editSettings
            }
            #if canImport(TagScan)
            TagScanView()
            #endif
        }.onAppear(perform: {
            refresh()
            
            #if targetEnvironment(macCatalyst)
            NSCursor.hide()
            #endif
        }).onDisappear(perform: {
            #if targetEnvironment(macCatalyst)
            NSCursor.unhide()
            #endif
        })
        
        .task {//From: https://fatbobman.com/en/posts/mastering_swiftui_task_modifier/
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(5 * Double(NSEC_PER_SEC)))
                withAnimation {
                    refresh()
                }
            }
        }
    }
    
    @MainActor private func refresh(){
        let now = Date()
        if let cId = settings.selectedCalendarId {
            currentEvent = GlobalEventStore.getActiveEvent(calendarId: cId, currentTime: now)
            nextEvent = GlobalEventStore.getNextEvent(calendarId: cId, currentTime: now)
        }
    }
}

#Preview {
    let _ = Settings.preview
    
    return DashboardView(state: .constant(.dashboard))
}
