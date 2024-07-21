import EventKit
import DataModel
import SwiftData
import SwiftUI
import Utility

public struct DashboardView: View {
    @Bindable var settings: Settings
    @Binding var state: AppState
    
    @State private var currentEvent: EKEvent?
    
    public init(settings: Bindable<Settings>, state: Binding<AppState>) {
        self._settings = settings
        self._state = state
    }
    
    public var body: some View {
        ZStack {
            VStack(alignment: .leading){
                if currentEvent != nil {
                    NowView(currentEvent: Binding($currentEvent)!)
                }
                SlideshowView()
                UpNextView()
            }
            AlertView()
        }.onAppear(perform: {
            if let cId = settings.selectedCalendarId {
                currentEvent = GlobalEventStore.getActiveEvent(calendarId: cId, currentTime: Date())
            }
        })
    }
}

#Preview {
    let container = Settings.preview
    let first = try! container.mainContext.fetch(FetchDescriptor<Settings>()).first!
    
    return DashboardView(settings: Bindable(first), state: .constant(.dashboard))
}
