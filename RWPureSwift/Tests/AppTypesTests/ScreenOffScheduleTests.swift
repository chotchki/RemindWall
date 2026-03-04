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
}
