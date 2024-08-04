import DataModel
import SwiftData
import SwiftUI

struct AlertLoaderView: View {
    @Environment(\.calendar) var calendar
    @Environment(\.modelContext) var modelContext
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    @State private var lateTrackees: [Trackee] = []
    
    var body: some View {
        AlertView(lateTrackees: lateTrackees)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(5 * Double(NSEC_PER_SEC))) //TODO: Change to a minute later
                
                let ft = FetchDescriptor<ReminderTimeModel>()
                let rTMs: [ReminderTimeModel] = (try? modelContext.fetch(ft)) ?? []
                let lateTrackeeIds = rTMs.filter{ $0.isLate(date: Date.now, calendar: calendar) }.map { $0.trackeeId }
                
                let ftt = FetchDescriptor<Trackee>()
                let trackees = (try? modelContext.fetch(ftt)) ?? []
                
                withAnimation {
                    lateTrackees = trackees.filter{ lateTrackeeIds.contains($0.id) }
                }
            }
        }
    }
}
