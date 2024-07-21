import EventKit
import SwiftUI
import Utility

struct UpNextView: View {
    private var nextEvent: EKEvent
    
    public init(nextEvent: EKEvent) {
        self.nextEvent = nextEvent
    }
    
    var body: some View {
        HStack{
            Text("Up Next:").font(.largeTitle)
            VStack(alignment: .leading){
                if let titleFirst = nextEvent.title?.first {
                    if titleFirst.isSimpleEmoji {
                        Text(String(titleFirst)).font(.title)
                        
                        Text("\(nextEvent.title.dropFirst(1)) in \(timeUntil())").font(.title).multilineTextAlignment(.leading)
                    } else {
                        Text("\(nextEvent.title) in \(timeUntil())").font(.title).multilineTextAlignment(.leading)
                    }
                } else {
                    Text("Unknown Event in \(timeUntil())").font(.title)
                }
            }
            
        }.padding()
    }
    
    func timeUntil() -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .brief
        formatter.allowedUnits = [.hour, .minute]
        
        return formatter.string(from: Date(), to: nextEvent.startDate) ?? "Unknown Time Until"
    }
}
