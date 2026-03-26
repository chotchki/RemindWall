import SwiftUI

struct NowView: View {
    let title: String

    var body: some View {
        HStack {
            Text("Now:")
                .font(.largeTitle)
            Text(title)
                .font(.title)
            Spacer()
        }
        .padding()
        .background(Color.white)
    }
}
