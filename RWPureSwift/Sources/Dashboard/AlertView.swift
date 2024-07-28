import DataModel
import SwiftData
import SwiftUI

struct AlertView: View {
    
    @Query(filter: #Predicate<Trackee> { t in
        !t.reminderTimes.isEmpty
    }) var trackees: [Trackee]
    
    private var lateTrackees: [Trackee] {
        let date = Date.now
        let calendar = Calendar.current
        return trackees.compactMap { t in
            for rt in t.reminderTimes {
                
            }
        }
    }
    
    var body: some View {
        VStack {
            Spacer()
            Text("Jax you are late for your meds!")
                .font(.custom("Overlay", size: 200, relativeTo: .largeTitle))
                .colorInvert()
                .frame(maxWidth:.infinity).multilineTextAlignment(.center)
            Spacer()
        }.background(Color.red.opacity(0.5))
    }
}

#Preview {
    AlertView()
}
