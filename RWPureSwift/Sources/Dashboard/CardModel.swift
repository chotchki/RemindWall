import Foundation

// The tier model from SPEC-DASHBOARD, encoded by TYPE rather than a field:
// RailCard is Tier 1 (the time-sensitive stack), AmbientChip is Tier 2 (the
// upper zone), and Tier 0 is never a card - it's the full-screen overlay.
// Gating stays with the source feature: a card that reaches the rail is
// already in-window; the rail only orders and caps.

/// Priority classes from SPEC-DASHBOARD: late/degraded things first, chrome
/// last. Lower raw value = more urgent = rendered lower in the stack
/// (Candidate A: urgency = height, most urgent at eye level).
public enum RailPriority: Int, Comparable, Sendable, CaseIterable {
    case lateBus = 1
    case slowRoute = 2
    case onTimeBus = 3
    case onTimeRoute = 4
    case upNext = 5
    case errorChip = 6

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One entry in the dashboard's time-sensitive rail.
public struct RailCard: Equatable, Identifiable, Sendable {
    public enum Content: Equatable, Sendable {
        case transit(route: String, label: String, etaText: String, isLate: Bool, isLive: Bool)
        case drive(label: String, etaText: String, isLate: Bool)
        case upNext(title: String, timeUntil: String, emoji: String?)
        case errorChip(message: String)
    }

    /// Stable across refreshes (e.g. "bus-<stopId>") so SwiftUI transitions
    /// track the card, not its contents.
    public let id: String
    public let priority: RailPriority
    /// Tiebreaker within a priority class: soonest first; nil sorts last.
    public let etaSeconds: TimeInterval?
    public let content: Content

    public init(
        id: String,
        priority: RailPriority,
        etaSeconds: TimeInterval? = nil,
        content: Content
    ) {
        self.id = id
        self.priority = priority
        self.etaSeconds = etaSeconds
        self.content = content
    }
}

/// An ambient (Tier 2) chip - glanceable, never urgent, renders in the upper
/// zone away from the rail. Battery (H1.4) is the first source.
public struct AmbientChip: Equatable, Identifiable, Sendable {
    public let id: String
    public let systemImage: String
    public let text: String

    public init(id: String, systemImage: String, text: String) {
        self.id = id
        self.systemImage = systemImage
        self.text = text
    }
}

/// The assembled rail: what renders, in what order, and how many got cut.
public struct DashboardRail: Equatable, Sendable {
    /// SPEC-DASHBOARD capacity: stack depth, not rail width.
    public static let wallCapacity = 4
    public static let padCapacity = 3

    /// The Mac target drives the wall monitor, the iOS target the iPads.
    public static var platformCapacity: Int {
        #if targetEnvironment(macCatalyst)
        wallCapacity
        #else
        padCapacity
        #endif
    }

    /// Most urgent first; Candidate A renders this bottom-up.
    public let visible: [RailCard]
    public let overflowCount: Int

    public static let empty = DashboardRail(visible: [], overflowCount: 0)

    public init(visible: [RailCard], overflowCount: Int) {
        self.visible = visible
        self.overflowCount = overflowCount
    }

    /// Sorts by (priority, soonest ETA, id) and caps at capacity. The id leg
    /// makes equal cards deterministic - a rail that reshuffles on every
    /// refresh reads as broken. Dropped cards surface as overflowCount, never
    /// silently.
    public static func assemble(
        _ cards: [RailCard],
        capacity: Int = wallCapacity
    ) -> DashboardRail {
        let ordered = cards.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            let lhsEta = lhs.etaSeconds ?? .infinity
            let rhsEta = rhs.etaSeconds ?? .infinity
            if lhsEta != rhsEta {
                return lhsEta < rhsEta
            }
            return lhs.id < rhs.id
        }
        return DashboardRail(
            visible: Array(ordered.prefix(capacity)),
            overflowCount: max(0, ordered.count - capacity)
        )
    }
}
