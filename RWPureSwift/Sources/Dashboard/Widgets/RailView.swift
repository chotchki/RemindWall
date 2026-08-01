import SwiftUI

/// SPEC-DASHBOARD wall/pad type scale. The Mac target drives the 32" LG wall
/// monitor, the iOS target the arm's-length iPads - the platform split IS the
/// viewing-distance split.
enum RailScale {
    #if targetEnvironment(macCatalyst)
    static let primary: CGFloat = 48
    static let secondary: CGFloat = 32
    static let chip: CGFloat = 24
    #else
    static let primary: CGFloat = 28
    static let secondary: CGFloat = 20
    static let chip: CGFloat = 14
    #endif
}

/// Candidate A's vertical rail: most urgent card at the BOTTOM (eye level on
/// the portrait panels), overflow chip above the stack. Renders whatever
/// DashboardRail.assemble produced - no ordering decisions live here, only
/// stacking direction.
public struct RailView: View {
    let rail: DashboardRail

    public init(rail: DashboardRail) {
        self.rail = rail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if rail.overflowCount > 0 {
                Text("+\(rail.overflowCount) more")
                    .font(.system(size: RailScale.chip, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.5))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityIdentifier("RailOverflow")
            }
            ForEach(rail.visible.reversed()) { card in
                RailCardView(card: card)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.default, value: rail)
    }
}

struct RailCardView: View {
    let card: RailCard

    var body: some View {
        switch card.content {
        case let .transit(route, label, etaText, isLate, isLive):
            cardRow {
                routeChip(route, background: Color(red: 0.18, green: 0.44, blue: 0.70))
                titleText(label)
                Spacer(minLength: 8)
                etaText_(etaText, dimmed: !isLive)
                if isLate { lateCapsule() }
            }

        case let .drive(label, etaText, isLate):
            cardRow {
                routeChip("🚗", background: Color(red: 0.30, green: 0.48, blue: 0.25))
                titleText(label)
                Spacer(minLength: 8)
                etaText_(etaText, dimmed: false)
                if isLate { lateCapsule() }
            }

        case let .upNext(title, timeUntil, emoji):
            cardRow {
                if let emoji {
                    Text(emoji).font(.system(size: RailScale.primary))
                }
                titleText(title)
                Spacer(minLength: 8)
                Text(timeUntil)
                    .font(.system(size: RailScale.secondary, weight: .semibold))
                    .opacity(0.9)
            }

        case let .errorChip(message):
            cardRow {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: RailScale.chip))
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(.system(size: RailScale.chip))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func cardRow(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 12) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.68))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func routeChip(_ text: String, background: Color) -> some View {
        Text(text)
            .font(.system(size: RailScale.primary, weight: .bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func titleText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: RailScale.secondary, weight: .semibold))
            .lineLimit(1)
    }

    private func etaText_(_ text: String, dimmed: Bool) -> some View {
        Text(text)
            .font(.system(size: RailScale.primary, weight: .bold))
            .italic(dimmed)
            .opacity(dimmed ? 0.75 : 1.0)
            .lineLimit(1)
    }

    private func lateCapsule() -> some View {
        Text("LATE")
            .font(.system(size: RailScale.chip, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(Color(red: 0.76, green: 0.18, blue: 0.12))
            .clipShape(Capsule())
    }
}

/// Tier 2 chips for the upper ambient zone (battery lands here in H1.4).
public struct AmbientChipsView: View {
    let chips: [AmbientChip]

    public init(chips: [AmbientChip]) {
        self.chips = chips
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(chips) { chip in
                HStack(spacing: 6) {
                    Image(systemName: chip.systemImage)
                    Text(chip.text)
                }
                .font(.system(size: RailScale.chip, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.55))
                .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.54))
                .clipShape(Capsule())
            }
        }
    }
}

#Preview("full rail") {
    ZStack {
        Color.gray
        VStack {
            Spacer()
            RailView(rail: DashboardRail.assemble([
                RailCard(
                    id: "bus-12", priority: .lateBus, etaSeconds: 240,
                    content: .transit(route: "12", label: "School bus", etaText: "4 min", isLate: true, isLive: true)
                ),
                RailCard(
                    id: "drive-school", priority: .slowRoute, etaSeconds: 1080,
                    content: .drive(label: "School run", etaText: "18 min", isLate: true)
                ),
                RailCard(
                    id: "bus-550", priority: .onTimeBus, etaSeconds: 840,
                    content: .transit(route: "550", label: "Commute", etaText: "14 min", isLate: false, isLive: false)
                ),
                RailCard(
                    id: "upnext", priority: .upNext, etaSeconds: 1500,
                    content: .upNext(title: "Dentist", timeUntil: "in 25 min", emoji: "🦷")
                ),
                RailCard(
                    id: "error-transit", priority: .errorChip,
                    content: .errorChip(message: "Cannot reach transit API")
                ),
            ]))
            .padding()
        }
    }
}
