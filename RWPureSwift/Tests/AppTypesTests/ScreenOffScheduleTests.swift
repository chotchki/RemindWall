import Testing

@testable import AppTypes

@Suite("ScreenOffSchedule Tests")
struct ScreenOffScheduleTests {

    @Test("default schedule is 10 PM to 6 AM")
    func defaultSchedule() {
        let schedule = ScreenOffSchedule.default
        #expect(schedule.startHour == 22)
        #expect(schedule.startMinute == 0)
        #expect(schedule.endHour == 6)
        #expect(schedule.endMinute == 0)
    }

    @Test("init with start and end times encodes correctly")
    func initWithTimes() {
        let schedule = ScreenOffSchedule(startHour: 21, startMinute: 30, endHour: 7, endMinute: 15)
        #expect(schedule.startHour == 21)
        #expect(schedule.startMinute == 30)
        #expect(schedule.endHour == 7)
        #expect(schedule.endMinute == 15)
    }

    @Test("startTimeDisplay formats AM correctly")
    func startTimeDisplayAM() {
        let schedule = ScreenOffSchedule(startHour: 9, startMinute: 30, endHour: 6, endMinute: 0)
        #expect(schedule.startTimeDisplay == "9:30 AM")
    }

    @Test("startTimeDisplay formats PM correctly")
    func startTimeDisplayPM() {
        let schedule = ScreenOffSchedule(startHour: 22, startMinute: 0, endHour: 6, endMinute: 0)
        #expect(schedule.startTimeDisplay == "10:00 PM")
    }

    @Test("endTimeDisplay formats AM correctly")
    func endTimeDisplayAM() {
        let schedule = ScreenOffSchedule(startHour: 22, startMinute: 0, endHour: 6, endMinute: 0)
        #expect(schedule.endTimeDisplay == "6:00 AM")
    }

    @Test("midnight displays as 12:00 AM")
    func midnightDisplay() {
        let schedule = ScreenOffSchedule(startHour: 0, startMinute: 0, endHour: 6, endMinute: 0)
        #expect(schedule.startTimeDisplay == "12:00 AM")
    }

    @Test("noon displays as 12:00 PM")
    func noonDisplay() {
        let schedule = ScreenOffSchedule(startHour: 12, startMinute: 0, endHour: 6, endMinute: 0)
        #expect(schedule.startTimeDisplay == "12:00 PM")
    }

    @Test("roundtrip preserves all values")
    func roundtrip() {
        let schedule = ScreenOffSchedule(startHour: 23, startMinute: 59, endHour: 0, endMinute: 1)
        #expect(schedule.startHour == 23)
        #expect(schedule.startMinute == 59)
        #expect(schedule.endHour == 0)
        #expect(schedule.endMinute == 1)
    }

    @Test("boundary values at hour 0 and minute 0")
    func boundaryZero() {
        let schedule = ScreenOffSchedule(startHour: 0, startMinute: 0, endHour: 0, endMinute: 0)
        #expect(schedule.startHour == 0)
        #expect(schedule.startMinute == 0)
        #expect(schedule.endHour == 0)
        #expect(schedule.endMinute == 0)
    }

    @Test("startTotalMinutes computes correctly")
    func startTotalMinutes() {
        let schedule = ScreenOffSchedule(startHour: 22, startMinute: 30, endHour: 6, endMinute: 0)
        #expect(schedule.startTotalMinutes == 1350)
    }

    @Test("endTotalMinutes computes correctly")
    func endTotalMinutes() {
        let schedule = ScreenOffSchedule(startHour: 22, startMinute: 0, endHour: 6, endMinute: 15)
        #expect(schedule.endTotalMinutes == 375)
    }

    // MARK: - isInOffWindow tests

    @Test("overnight window: 22:00-06:00, time 23:00 is in window")
    func overnightInWindow() {
        let schedule = ScreenOffSchedule(startHour: 22, startMinute: 0, endHour: 6, endMinute: 0)
        #expect(schedule.isInOffWindow(currentTotalMinutes: 23 * 60) == true)
    }

    @Test("overnight window: 22:00-06:00, time 05:59 is in window")
    func overnightEndBoundary() {
        let schedule = ScreenOffSchedule(startHour: 22, startMinute: 0, endHour: 6, endMinute: 0)
        #expect(schedule.isInOffWindow(currentTotalMinutes: 5 * 60 + 59) == true)
    }

    @Test("overnight window: 22:00-06:00, time 06:00 is NOT in window")
    func overnightExactEnd() {
        let schedule = ScreenOffSchedule(startHour: 22, startMinute: 0, endHour: 6, endMinute: 0)
        #expect(schedule.isInOffWindow(currentTotalMinutes: 6 * 60) == false)
    }

    @Test("overnight window: 22:00-06:00, time 12:00 is NOT in window")
    func overnightMidday() {
        let schedule = ScreenOffSchedule(startHour: 22, startMinute: 0, endHour: 6, endMinute: 0)
        #expect(schedule.isInOffWindow(currentTotalMinutes: 12 * 60) == false)
    }

    @Test("same-day window: 02:00-14:00, time 10:00 is in window")
    func sameDayInWindow() {
        let schedule = ScreenOffSchedule(startHour: 2, startMinute: 0, endHour: 14, endMinute: 0)
        #expect(schedule.isInOffWindow(currentTotalMinutes: 10 * 60) == true)
    }

    @Test("same-day window: 02:00-14:00, time 01:00 is NOT in window")
    func sameDayBeforeStart() {
        let schedule = ScreenOffSchedule(startHour: 2, startMinute: 0, endHour: 14, endMinute: 0)
        #expect(schedule.isInOffWindow(currentTotalMinutes: 1 * 60) == false)
    }

    @Test("degenerate window: start == end, always returns false")
    func degenerateWindow() {
        let schedule = ScreenOffSchedule(startHour: 10, startMinute: 0, endHour: 10, endMinute: 0)
        #expect(schedule.isInOffWindow(currentTotalMinutes: 10 * 60) == false)
    }

    @Test("midnight boundary: time 00:00 in overnight window 22:00-06:00")
    func midnightInOvernight() {
        let schedule = ScreenOffSchedule(startHour: 22, startMinute: 0, endHour: 6, endMinute: 0)
        #expect(schedule.isInOffWindow(currentTotalMinutes: 0) == true)
    }

    @Test("exact start time is in window")
    func exactStartInWindow() {
        let schedule = ScreenOffSchedule(startHour: 22, startMinute: 0, endHour: 6, endMinute: 0)
        #expect(schedule.isInOffWindow(currentTotalMinutes: 22 * 60) == true)
    }
}
