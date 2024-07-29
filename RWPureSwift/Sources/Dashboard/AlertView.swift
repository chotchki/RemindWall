import DataModel
import SwiftData
import SwiftUI

public struct AlertView: View {
    @Environment(\.calendar) var calendar
    @Environment(\.modelContext) var modelContext
    
    @State var lateTrackees: [Trackee] = []
        
    public var body: some View {
        VStack {
            if !lateTrackees.isEmpty {
                Spacer()
                ForEach(lateTrackees){ lt in
                    Text("\(lt.name) you are late for your meds!")
                        .font(.custom("Overlay", size: 200.0 / CGFloat(lateTrackees.count), relativeTo: .largeTitle))
                        .colorInvert()
                        .frame(maxWidth:.infinity).multilineTextAlignment(.center)
                }
                Spacer()
            }
        }.background(Color.red.opacity(0.5))
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
