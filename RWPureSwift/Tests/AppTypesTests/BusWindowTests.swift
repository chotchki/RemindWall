import Foundation
import Testing

@testable import AppTypes

@Suite("BusWindow Tests")
struct BusWindowTests {

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    // April 5, 2026 is a Sunday. Day-by-day offsets give us deterministic weekdays.
    private static func date(weekdayOffset: Int, hour: Int, minute: Int) -> Date {
        utc.date(from: DateComponents(
            year: 2026, month: 4, day: 5 + weekdayOffset,
            hour: hour, minute: minute
        ))!
    }

    @Test("default is Mon-Fri 06:30-09:00")
    func defaultValues() {
        let w = BusWindow.default
        #expect(w.startHour == 6)
        #expect(w.startMinute == 30)
        #expect(w.endHour == 9)
        #expect(w.endMinute == 0)
        #expect(w.weekdays == [.Monday, .Tuesday, .Wednesday, .Thursday, .Friday])
    }

    @Test("init encodes all fields and round-trips")
    func roundtrip() {
        let w = BusWindow(
            weekdays: [.Sunday, .Saturday],
            startHour: 23, startMinute: 59,
            endHour: 0, endMinute: 1
        )
        #expect(w.startHour == 23)
        #expect(w.startMinute == 59)
        #expect(w.endHour == 0)
        #expect(w.endMinute == 1)
        #expect(w.weekdays == [.Sunday, .Saturday])
    }

    @Test("empty weekday set encodes as zero mask")
    func emptyWeekdays() {
        let w = BusWindow(
            weekdays: [],
            startHour: 6, startMinute: 0,
            endHour: 9, endMinute: 0
        )
        #expect(w.weekdays.isEmpty)
    }

    @Test("all weekdays encode to mask 0b1111111")
    func allWeekdays() {
        let w = BusWindow(
            weekdays: Set(DaysOfWeek.allCases),
            startHour: 6, startMinute: 0,
            endHour: 9, endMinute: 0
        )
        #expect(w.weekdays == Set(DaysOfWeek.allCases))
    }

    @Test("startTimeDisplay formats AM correctly")
    func startTimeDisplayAM() {
        let w = BusWindow(weekdays: [], startHour: 6, startMinute: 30, endHour: 9, endMinute: 0)
        #expect(w.startTimeDisplay == "6:30 AM")
    }

    @Test("startTimeDisplay formats PM correctly")
    func startTimeDisplayPM() {
        let w = BusWindow(weekdays: [], startHour: 22, startMinute: 0, endHour: 23, endMinute: 0)
        #expect(w.startTimeDisplay == "10:00 PM")
    }

    @Test("midnight displays as 12:00 AM")
    func midnightDisplay() {
        let w = BusWindow(weekdays: [], startHour: 0, startMinute: 0, endHour: 1, endMinute: 0)
        #expect(w.startTimeDisplay == "12:00 AM")
    }

    @Test("noon displays as 12:00 PM")
    func noonDisplay() {
        let w = BusWindow(weekdays: [], startHour: 12, startMinute: 0, endHour: 13, endMinute: 0)
        #expect(w.startTimeDisplay == "12:00 PM")
    }

    @Test("startTotalMinutes computes correctly")
    func startTotalMinutes() {
        let w = BusWindow(weekdays: [], startHour: 6, startMinute: 30, endHour: 9, endMinute: 0)
        #expect(w.startTotalMinutes == 390)
    }

    @Test("endTotalMinutes computes correctly")
    func endTotalMinutes() {
        let w = BusWindow(weekdays: [], startHour: 6, startMinute: 30, endHour: 9, endMinute: 15)
        #expect(w.endTotalMinutes == 555)
    }

    // MARK: - isInWindow

    @Test("default window: Monday 07:00 is in window")
    func defaultMonday0700() {
        // April 6, 2026 is a Monday (offset 1 from Sunday April 5)
        let date = Self.date(weekdayOffset: 1, hour: 7, minute: 0)
        #expect(BusWindow.default.isInWindow(date: date, calendar: Self.utc))
    }

    @Test("default window: Sunday 07:00 is NOT in window")
    func defaultSunday0700() {
        let date = Self.date(weekdayOffset: 0, hour: 7, minute: 0)
        #expect(BusWindow.default.isInWindow(date: date, calendar: Self.utc) == false)
    }

    @Test("default window: Saturday 07:00 is NOT in window")
    func defaultSaturday0700() {
        let date = Self.date(weekdayOffset: 6, hour: 7, minute: 0)
        #expect(BusWindow.default.isInWindow(date: date, calendar: Self.utc) == false)
    }

    @Test("default window: Friday 06:30 (exact start) is in window")
    func defaultFridayExactStart() {
        let date = Self.date(weekdayOffset: 5, hour: 6, minute: 30)
        #expect(BusWindow.default.isInWindow(date: date, calendar: Self.utc))
    }

    @Test("default window: Friday 09:00 (exact end) is NOT in window")
    func defaultFridayExactEnd() {
        let date = Self.date(weekdayOffset: 5, hour: 9, minute: 0)
        #expect(BusWindow.default.isInWindow(date: date, calendar: Self.utc) == false)
    }

    @Test("default window: Friday 06:29 (one minute before start) is NOT in window")
    func defaultFridayOneMinuteBefore() {
        let date = Self.date(weekdayOffset: 5, hour: 6, minute: 29)
        #expect(BusWindow.default.isInWindow(date: date, calendar: Self.utc) == false)
    }

    @Test("default window: Friday 08:59 (one minute before end) is in window")
    func defaultFridayOneMinuteBeforeEnd() {
        let date = Self.date(weekdayOffset: 5, hour: 8, minute: 59)
        #expect(BusWindow.default.isInWindow(date: date, calendar: Self.utc))
    }

    @Test("overnight window: Monday 23:00 (start=22:00, end=06:00) is in window")
    func overnightInWindow() {
        let w = BusWindow(
            weekdays: [.Monday],
            startHour: 22, startMinute: 0,
            endHour: 6, endMinute: 0
        )
        let date = Self.date(weekdayOffset: 1, hour: 23, minute: 0)
        #expect(w.isInWindow(date: date, calendar: Self.utc))
    }

    @Test("overnight window: Monday 03:00 wraps and is in window")
    func overnightWrapInWindow() {
        let w = BusWindow(
            weekdays: [.Monday],
            startHour: 22, startMinute: 0,
            endHour: 6, endMinute: 0
        )
        let date = Self.date(weekdayOffset: 1, hour: 3, minute: 0)
        #expect(w.isInWindow(date: date, calendar: Self.utc))
    }

    @Test("degenerate window (start == end) is never in window")
    func degenerateWindow() {
        let w = BusWindow(
            weekdays: Set(DaysOfWeek.allCases),
            startHour: 10, startMinute: 0,
            endHour: 10, endMinute: 0
        )
        let date = Self.date(weekdayOffset: 1, hour: 10, minute: 0)
        #expect(w.isInWindow(date: date, calendar: Self.utc) == false)
    }

    @Test("malformed raw value falls back to defaults without crashing")
    func malformedRawValue() {
        let bogus = BusWindow(rawValue: "not-a-window")
        #expect(bogus.weekdays.isEmpty)
        #expect(bogus.startHour == 6)
        #expect(bogus.endHour == 9)
        let date = Self.date(weekdayOffset: 1, hour: 7, minute: 0)
        #expect(bogus.isInWindow(date: date, calendar: Self.utc) == false)
    }
}
