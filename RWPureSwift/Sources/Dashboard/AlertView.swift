import DataModel
import SwiftData
import SwiftUI

struct AlertView: View {
    let calendar = Calendar.current
    
    @Query(filter: #Predicate<Trackee> { t in
        !t.reminderTimes.isEmpty
    }) var trackees: [Trackee]
    
    @State private var currentTime = Date.now
    
    private var lateTrackees: [Trackee] {
        return trackees.compactMap { t in
            for rt in t.reminderTimes {
                if rt.isLate(date: currentTime, calendar: calendar) {
                    return t
                }
            }
            return nil
        }
    }
    
    var body: some View {
        VStack {
            Spacer()
            ForEach(lateTrackees){ lt in
                Text("\(lt.name) you are late for your meds!")
                    .font(.custom("Overlay", size: 200.0 / CGFloat(lateTrackees.count), relativeTo: .largeTitle))
                    .colorInvert()
                    .frame(maxWidth:.infinity).multilineTextAlignment(.center)
            }
            Spacer()
        }.background(Color.red.opacity(0.5))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(60 * Double(NSEC_PER_SEC)))
                withAnimation {
                    currentTime = Date.now
                }
            }
        }
    }
}

#Preview {
    AlertView()
}
