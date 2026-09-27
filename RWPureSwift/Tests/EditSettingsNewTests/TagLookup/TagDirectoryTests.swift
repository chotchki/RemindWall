import AppTypes
import Dao
import Foundation
import Testing

@testable import EditSettingsNew_TagLookup

@Suite("TagDirectory")
struct TagDirectoryTests {
    let alice = Trackee(id: Trackee.ID(UUID(0)), name: "Alice")
    let bob = Trackee(id: Trackee.ID(UUID(1)), name: "Bob", remindersEnabled: false)
    let morningCup = TagSerial([0x01])
    let eveningCup = TagSerial([0x02])

    private func reminder(
        _ n: Int,
        _ trackee: Trackee.ID,
        day: DaysOfWeek,
        hour: Int,
        minute: Int = 0,
        tag: TagSerial?,
        lastScan: Date? = nil
    ) -> ReminderTime {
        ReminderTime(
            id: ReminderTime.ID(UUID(n + 100)),
            weekDay: day.rawValue,
            hour: hour,
            minute: minute,
            associatedTag: tag,
            lastScan: lastScan,
            trackeeId: trackee
        )
    }

    @Test("a daily dose collapses to one cup with an Every day slot")
    func dailyCupCollapses() {
        let reminders = DaysOfWeek.allCases.enumerated().map { i, day in
            reminder(i, alice.id, day: day, hour: 8, tag: morningCup)
        }
        let directory = TagDirectory(trackees: [alice], reminders: reminders)

        #expect(directory.people.count == 1)
        #expect(directory.people[0].cups.map(\.slots) == [["8:00 AM · Every day"]])
        #expect(directory.people[0].untaggedReminderCount == 0)
    }

    @Test("owners(of:) resolves the scanned tag to its person and slot")
    func ownersOfTag() {
        let directory = TagDirectory(trackees: [alice, bob], reminders: [
            reminder(0, alice.id, day: .Monday, hour: 8, tag: morningCup),
            reminder(1, alice.id, day: .Monday, hour: 20, minute: 30, tag: eveningCup),
            reminder(2, bob.id, day: .Tuesday, hour: 9, tag: TagSerial([0x03])),
        ])

        let owners = directory.owners(of: eveningCup)
        #expect(owners.map(\.person.name) == ["Alice"])
        #expect(owners.first?.cup.slots == ["8:30 PM · Monday"])
        #expect(directory.owners(of: TagSerial([0xFF])).isEmpty)
        #expect(directory.allTags == [morningCup, eveningCup, TagSerial([0x03])])
    }

    @Test("a tag shared across people is flagged on both sides")
    func sharedTagFlagged() {
        let directory = TagDirectory(trackees: [alice, bob], reminders: [
            reminder(0, alice.id, day: .Monday, hour: 8, tag: morningCup),
            reminder(1, bob.id, day: .Monday, hour: 8, tag: morningCup),
        ])

        let owners = directory.owners(of: morningCup)
        #expect(owners.map(\.person.name) == ["Alice", "Bob"])
        #expect(owners.map(\.cup.sharedWith) == [["Bob"], ["Alice"]])
    }

    @Test("untagged reminders are counted, trackees without reminders still listed")
    func untaggedAndEmpty() {
        let directory = TagDirectory(trackees: [bob, alice], reminders: [
            reminder(0, alice.id, day: .Monday, hour: 8, tag: nil),
            reminder(1, alice.id, day: .Tuesday, hour: 8, tag: nil),
        ])

        #expect(directory.people.map(\.name) == ["Alice", "Bob"])
        #expect(directory.people[0].cups.isEmpty)
        #expect(directory.people[0].untaggedReminderCount == 2)
        #expect(directory.people[1].cups.isEmpty)
        #expect(directory.people[1].remindersEnabled == false)
    }

    @Test("reminders whose trackee row is gone surface under Unknown trackee")
    func orphanReminders() {
        let ghost = Trackee.ID(UUID(9))
        let directory = TagDirectory(trackees: [alice], reminders: [
            reminder(0, ghost, day: .Friday, hour: 7, tag: morningCup),
        ])

        #expect(directory.people.map(\.name) == ["Alice", "Unknown trackee"])
        #expect(directory.owners(of: morningCup).map(\.person.id) == [ghost])
    }

    @Test("cups sort in board order: weekday first, then time of day")
    func cupOrdering() {
        let sundayNight = TagSerial([0x0A])
        let mondayMorning = TagSerial([0x0B])
        let sundayMorning = TagSerial([0x0C])
        let directory = TagDirectory(trackees: [alice], reminders: [
            reminder(0, alice.id, day: .Monday, hour: 8, tag: mondayMorning),
            reminder(1, alice.id, day: .Sunday, hour: 20, tag: sundayNight),
            reminder(2, alice.id, day: .Sunday, hour: 8, tag: sundayMorning),
        ])

        #expect(directory.people[0].cups.map(\.tag) == [sundayMorning, sundayNight, mondayMorning])
    }

    @Test("lastScan is the most recent across the cup's reminders")
    func lastScanIsMostRecent() {
        let earlier = Date(timeIntervalSince1970: 1_000)
        let later = Date(timeIntervalSince1970: 2_000)
        let directory = TagDirectory(trackees: [alice], reminders: [
            reminder(0, alice.id, day: .Monday, hour: 8, tag: morningCup, lastScan: later),
            reminder(1, alice.id, day: .Tuesday, hour: 8, tag: morningCup, lastScan: earlier),
            reminder(2, alice.id, day: .Wednesday, hour: 8, tag: morningCup),
        ])

        #expect(directory.people[0].cups[0].lastScan == later)
        #expect(directory.people[0].cups[0].slots == ["8:00 AM · Mon, Tue, Wed"])
    }

    @Test("day sets name their common shapes")
    func daysText() {
        #expect(TagDirectory.daysText(Set(DaysOfWeek.allCases)) == "Every day")
        #expect(TagDirectory.daysText([.Monday, .Tuesday, .Wednesday, .Thursday, .Friday]) == "Weekdays")
        #expect(TagDirectory.daysText([.Saturday, .Sunday]) == "Weekends")
        #expect(TagDirectory.daysText([.Wednesday]) == "Wednesday")
        #expect(TagDirectory.daysText([.Friday, .Sunday, .Wednesday]) == "Sun, Wed, Fri")
    }

    @Test("times render 12-hour with midnight and noon as 12")
    func timeText() {
        #expect(TagDirectory.timeText(hour: 0, minute: 5) == "12:05 AM")
        #expect(TagDirectory.timeText(hour: 12, minute: 0) == "12:00 PM")
        #expect(TagDirectory.timeText(hour: 23, minute: 45) == "11:45 PM")
    }

    @Test("one cup can span two times of day, one line each")
    func multipleTimesOnOneCup() {
        let directory = TagDirectory(trackees: [alice], reminders: [
            reminder(0, alice.id, day: .Monday, hour: 20, tag: morningCup),
            reminder(1, alice.id, day: .Monday, hour: 8, tag: morningCup),
            reminder(2, alice.id, day: .Tuesday, hour: 8, tag: morningCup),
        ])

        #expect(directory.people[0].cups[0].slots == ["8:00 AM · Mon, Tue", "8:00 PM · Monday"])
    }
}
