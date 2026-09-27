import AppTypes
import Dao
import Foundation
import Tagged

/// Who owns which tag (cup), built fresh from the DB on every read. A tag
/// lives on each ReminderTime, so one physical cup = one distinct tag across
/// a person's reminders.
public struct TagDirectory: Equatable, Sendable {
    public var people: [Person]

    public struct Person: Equatable, Sendable, Identifiable {
        public let id: Trackee.ID
        public let name: String
        public let remindersEnabled: Bool
        public let cups: [Cup]
        /// Reminders with no tag; no scan can ever credit these.
        public let untaggedReminderCount: Int
    }

    public struct Cup: Equatable, Sendable, Identifiable {
        public var id: TagSerial { tag }
        public let tag: TagSerial
        /// One line per time of day, e.g. "8:00 AM · Every day".
        public let slots: [String]
        public let lastScan: Date?
        /// Other people with reminders on this same tag. A dashboard scan
        /// credits whichever reminder is due, so the cup is ambiguous.
        public let sharedWith: [String]
    }

    /// One person's claim on a scanned tag.
    public struct Owner: Equatable, Sendable, Identifiable {
        public var id: Trackee.ID { person.id }
        public let person: Person
        public let cup: Cup
    }

    public static let empty = TagDirectory(people: [])

    public init(people: [Person]) {
        self.people = people
    }

    public init(trackees: [Trackee], reminders: [ReminderTime]) {
        let trackeesById = Dictionary(trackees.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remindersByTrackee = Dictionary(grouping: reminders, by: \.trackeeId)

        // Sync can leave reminders whose trackee row is gone (reminderTimes
        // has no FK since the cascade migration); keep them visible.
        let orphanIds = remindersByTrackee.keys.filter { trackeesById[$0] == nil }
        let identities: [(id: Trackee.ID, name: String, enabled: Bool)] =
            trackees.map { ($0.id, $0.name, $0.remindersEnabled) }
            + orphanIds.map { ($0, "Unknown trackee", true) }

        let ownerIdsByTag: [TagSerial: Set<Trackee.ID>] = reminders.reduce(into: [:]) { acc, reminder in
            if let tag = reminder.associatedTag {
                acc[tag, default: []].insert(reminder.trackeeId)
            }
        }
        let nameOf = Dictionary(identities.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        people = identities.map { identity in
            let own = remindersByTrackee[identity.id] ?? []
            let byTag = Dictionary(grouping: own.filter { $0.associatedTag != nil }, by: { $0.associatedTag! })
            let cups = byTag.map { tag, tagged in
                Cup(
                    tag: tag,
                    slots: Self.slotSummary(tagged),
                    lastScan: tagged.compactMap(\.lastScan).max(),
                    sharedWith: (ownerIdsByTag[tag] ?? [])
                        .subtracting([identity.id])
                        .compactMap { nameOf[$0] }
                        .sorted()
                )
            }
            .sorted { lhs, rhs in
                let l = Self.firstSlotKey(byTag[lhs.tag]!), r = Self.firstSlotKey(byTag[rhs.tag]!)
                return l != r ? l < r : lhs.tag.hexa < rhs.tag.hexa
            }
            return Person(
                id: identity.id,
                name: identity.name,
                remindersEnabled: identity.enabled,
                cups: cups,
                untaggedReminderCount: own.count(where: { $0.associatedTag == nil })
            )
        }
        .sorted { lhs, rhs in
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            return order != .orderedSame ? order == .orderedAscending : lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
        }
    }

    public var allTags: Set<TagSerial> {
        Set(people.flatMap { $0.cups.map(\.tag) })
    }

    public func owners(of tag: TagSerial) -> [Owner] {
        people.compactMap { person in
            person.cups.first { $0.tag == tag }.map { Owner(person: person, cup: $0) }
        }
    }

    // MARK: - Slot formatting

    /// Groups by time of day so a daily dose reads "8:00 AM · Every day"
    /// instead of seven rows; a per-day cup reads "8:00 AM · Monday".
    static func slotSummary(_ reminders: [ReminderTime]) -> [String] {
        let byTime = Dictionary(grouping: reminders, by: { $0.hour * 60 + $0.minute })
        return byTime.keys.sorted().map { minuteOfDay in
            let days = Set(byTime[minuteOfDay]!.compactMap { DaysOfWeek(rawValue: $0.weekDay) })
            return "\(timeText(hour: minuteOfDay / 60, minute: minuteOfDay % 60)) · \(daysText(days))"
        }
    }

    static func daysText(_ days: Set<DaysOfWeek>) -> String {
        let weekdays: Set<DaysOfWeek> = [.Monday, .Tuesday, .Wednesday, .Thursday, .Friday]
        let weekend: Set<DaysOfWeek> = [.Saturday, .Sunday]
        switch days {
        case Set(DaysOfWeek.allCases): return "Every day"
        case weekdays: return "Weekdays"
        case weekend: return "Weekends"
        default:
            let ordered = DaysOfWeek.allCases.filter(days.contains)
            if ordered.count == 1 { return String(describing: ordered[0]) }
            return ordered.map { String(String(describing: $0).prefix(3)) }.joined(separator: ", ")
        }
    }

    static func timeText(hour: Int, minute: Int) -> String {
        let hour12 = hour % 12
        return String(format: "%d:%02d %@", hour12 == 0 ? 12 : hour12, minute, hour < 12 ? "AM" : "PM")
    }

    /// Week order (Sunday first, matching DaysOfWeek), then time of day, so
    /// a weekly board's cups list in the order they sit on it.
    private static func firstSlotKey(_ reminders: [ReminderTime]) -> Int {
        reminders.map { $0.weekDay * 24 * 60 + $0.hour * 60 + $0.minute }.min() ?? .max
    }
}
