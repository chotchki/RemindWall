import SwiftUI
import Utility

/// Tier 2 ambient banner for the in-progress event. Same capsule language as
/// the ambient chips, sized up to secondary scale — it's the headline of the
/// ambient zone, not a chore chip.
struct NowView: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            if let first = title.first, first.isSimpleEmoji {
                Text(String(first))
                Text(title.dropFirst(1).trimmingCharacters(in: .whitespaces))
                    .lineLimit(1)
            } else {
                Image(systemName: "calendar")
                Text(title)
                    .lineLimit(1)
            }
        }
        .font(.system(size: RailScale.secondary, weight: .semibold))
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.55))
        .foregroundStyle(.white)
        .clipShape(Capsule())
    }
}

#Preview("plain and emoji titles") {
    ZStack {
        Color.gray
        VStack(alignment: .leading, spacing: 12) {
            NowView(title: "Piano lesson")
            NowView(title: "🦷 Dentist")
        }
    }
}
