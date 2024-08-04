import DataModel
import SwiftUI

public struct AlertView: View {
    let lateTrackees: [Trackee]
    
    var names: [String] {
        lateTrackees.map({$0.name})
    }
        
    public var body: some View {
        VStack {
            if !lateTrackees.isEmpty {
                Spacer()
                Text("\(ListFormatter.localizedString(byJoining: names)) you are late for your meds!")
                        .font(.custom("Overlay", size: 200.0, relativeTo: .largeTitle))
                        .colorInvert()
                        .frame(maxWidth:.infinity).multilineTextAlignment(.center)
                Spacer()
            }
        }.background(Color.red.opacity(0.5))
        
    }
}

#Preview("single") {
    let _ = Trackee.preview
    let trackees = [Trackee(name: "Bob")]
    return ZStack{
        VStack{
            Spacer()
        }.background(Color.white)
        AlertView(lateTrackees: trackees)
    }
}

#Preview("two") {
    let _ = Trackee.preview
    let trackees = [Trackee(name: "Bob"), Trackee(name: "Sue")]
    return ZStack{
        VStack{
            Spacer()
        }.background(Color.white)
        AlertView(lateTrackees: trackees)
    }
}

#Preview("three") {
    let _ = Trackee.preview
    let trackees = [Trackee(name: "Bob"), Trackee(name: "Sue"), Trackee(name: "Christopher")]
    return ZStack{
        VStack{
            Spacer()
        }.background(Color.white)
        AlertView(lateTrackees: trackees)
    }
}


