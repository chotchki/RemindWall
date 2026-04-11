import SwiftUI

public struct AlertView: View {
    let lateTrackeeNames: [String]
    let dayOfWeek: String

    public var body: some View {
        VStack {
            if !lateTrackeeNames.isEmpty {
                Spacer()
                Text("It's \(dayOfWeek) — \(ListFormatter.localizedString(byJoining: lateTrackeeNames)) you are late for your meds!")
                    .font(.custom("Overlay", size: 200.0, relativeTo: .largeTitle))
                    .colorInvert()
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                Spacer()
            }
        }
        .background(Color.red.opacity(0.5))
    }
}

#Preview("single") {
    ZStack {
        VStack {
            Spacer()
        }.background(Color.white)
        AlertView(lateTrackeeNames: ["Bob"], dayOfWeek: "Monday")
    }
}

#Preview("two") {
    ZStack {
        VStack {
            Spacer()
        }.background(Color.white)
        AlertView(lateTrackeeNames: ["Bob", "Sue"], dayOfWeek: "Wednesday")
    }
}

#Preview("three") {
    ZStack {
        VStack {
            Spacer()
        }.background(Color.white)
        AlertView(lateTrackeeNames: ["Bob", "Sue", "Christopher"], dayOfWeek: "Friday")
    }
}
