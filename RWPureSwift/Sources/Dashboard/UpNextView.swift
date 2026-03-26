import SwiftUI

struct UpNextView: View {
    let title: String
    let timeUntil: String
    let leadingEmoji: String?

    var body: some View {
        HStack {
            Text("Up Next:").font(.largeTitle)
            VStack(alignment: .leading) {
                if let emoji = leadingEmoji {
                    Text(emoji).font(.title)
                    Text("\(title) in \(timeUntil)")
                        .font(.title)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("\(title) in \(timeUntil)")
                        .font(.title)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer()
        }
        .padding()
        .background(Color.white)
    }
}
