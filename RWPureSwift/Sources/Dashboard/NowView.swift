import EventKit
import SwiftUI
import Utility

struct NowView: View {
    private var currentEvent: EKEvent
    
    public init(currentEvent: EKEvent) {
        self.currentEvent = currentEvent
    }
    
    var body: some View {
        HStack{
            Text("Now:")
                .font(.largeTitle)
            Text(currentEvent.title)
                .font(.title)
        }.padding()
    }
}
