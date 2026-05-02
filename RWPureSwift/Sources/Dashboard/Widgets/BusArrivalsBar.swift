import Dao
import SwiftUI
import Tagged

public struct BusArrivalsBar: View {
    let arrivals: [DisplayArrival]
    let errorMessage: String?

    public init(arrivals: [DisplayArrival], errorMessage: String?) {
        self.arrivals = arrivals
        self.errorMessage = errorMessage
    }

    public var body: some View {
        if arrivals.isEmpty, let error = errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Cannot reach transit API: \(error)")
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.7))
            .foregroundStyle(.white)
        } else if !arrivals.isEmpty {
            HStack(spacing: 16) {
                ForEach(arrivals) { arrival in
                    arrivalCard(arrival)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.7))
            .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func arrivalCard(_ arrival: DisplayArrival) -> some View {
        HStack(spacing: 8) {
            Text(arrival.routeShortName)
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(arrival.label)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(arrival.etaText)
                        .font(.caption)
                        .italic(!arrival.isLive)
                        .opacity(arrival.isLive ? 1.0 : 0.7)
                    if arrival.isLate {
                        Label("late", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

#Preview("on time") {
    ZStack {
        VStack { Spacer() }.background(Color.gray.opacity(0.3))
        VStack {
            Spacer()
            BusArrivalsBar(
                arrivals: [
                    DisplayArrival(
                        id: .init(rawValue: UUID()),
                        label: "School bus",
                        routeShortName: "12",
                        etaText: "in 4 min",
                        isLate: false,
                        isLive: true
                    )
                ],
                errorMessage: nil
            )
        }
    }
}

#Preview("late + scheduled-only") {
    ZStack {
        VStack { Spacer() }.background(Color.gray.opacity(0.3))
        VStack {
            Spacer()
            BusArrivalsBar(
                arrivals: [
                    DisplayArrival(
                        id: .init(rawValue: UUID()),
                        label: "School bus",
                        routeShortName: "12",
                        etaText: "in 6 min",
                        isLate: true,
                        isLive: true
                    ),
                    DisplayArrival(
                        id: .init(rawValue: UUID()),
                        label: "Wife's commute",
                        routeShortName: "550",
                        etaText: "scheduled in 14 min",
                        isLate: false,
                        isLive: false
                    )
                ],
                errorMessage: nil
            )
        }
    }
}

#Preview("error") {
    ZStack {
        VStack { Spacer() }.background(Color.gray.opacity(0.3))
        VStack {
            Spacer()
            BusArrivalsBar(arrivals: [], errorMessage: "unauthorized")
        }
    }
}
