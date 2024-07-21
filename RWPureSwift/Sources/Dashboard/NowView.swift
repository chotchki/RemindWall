import EventKit
import SwiftUI
import Utility

struct NowView: View {
    @Binding private var currentEvent: EKEvent
    
    public init(currentEvent: Binding<EKEvent>) {
        self._currentEvent = currentEvent
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
