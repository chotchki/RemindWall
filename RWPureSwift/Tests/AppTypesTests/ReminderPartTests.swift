import AppTypes
import Foundation
import Testing

@Test("Gen Early Late", arguments: [
    (ReminderPart(weekDay: .Sunday, hour: 0, minute: 0), ReminderPart(weekDay: .Saturday, hour: 22, minute: 0), ReminderPart(weekDay: .Sunday, hour: 4, minute: 0)),
    (ReminderPart(weekDay:.Sunday, hour: 12, minute: 0), ReminderPart(weekDay: .Sunday, hour: 10, minute: 0), ReminderPart(weekDay: .Sunday, hour: 16, minute: 0)),
    (ReminderPart(weekDay: .Saturday, hour: 23, minute: 55), ReminderPart(weekDay: .Saturday, hour: 21, minute: 55), ReminderPart(weekDay: .Sunday, hour: 3, minute: 55))
])
func generateEarlyLate(rt: ReminderPart, early: ReminderPart, late: ReminderPart){
    #expect(rt.earlyScan() == early)
    #expect(rt.lateReminder() == late)
}

@Test("Scan Window Tests", arguments: [
    //Simple Examples
    ("2025-11-15T21:30:00Z", ReminderPart(weekDay: .Sunday, hour: 0, minute: 0), false, false),
    ("2025-11-15T22:30:00Z", ReminderPart(weekDay: .Sunday, hour: 0, minute: 0), true, false),
    ("2025-11-15T23:30:00Z", ReminderPart(weekDay: .Sunday, hour: 0, minute: 0), true, false),
    ("2025-11-16T00:30:00Z", ReminderPart(weekDay: .Sunday, hour: 0, minute: 0), true, true),
    ("2025-11-16T01:30:00Z", ReminderPart(weekDay: .Sunday, hour: 0, minute: 0), true, true),
    ("2025-11-16T02:30:00Z", ReminderPart(weekDay: .Sunday, hour: 0, minute: 0), true, true),
    ("2025-11-16T03:30:00Z", ReminderPart(weekDay: .Sunday, hour: 0, minute: 0), true, true),
    ("2025-11-16T04:30:00Z", ReminderPart(weekDay: .Sunday, hour: 0, minute: 0), false, false),
    
    //Edge Cases
    ("2025-11-15T21:59:59Z", ReminderPart(weekDay: .Sunday, hour: 0, minute: 0), false, false),
    ("2025-11-15T22:00:00Z", ReminderPart(weekDay: .Sunday, hour: 0, minute: 0), true, false),
    ("2025-11-15T23:59:59Z", ReminderPart(weekDay: .Sunday, hour: 0, minute: 0), true, false),
    ("2025-11-16T00:00:00Z", ReminderPart(weekDay: .Sunday, hour: 0, minute: 0), true, true),
    ("2025-11-16T03:59:59Z", ReminderPart(weekDay: .Sunday, hour: 0, minute: 0), true, true),
    ("2025-11-16T04:00:00Z", ReminderPart(weekDay: .Sunday, hour: 0, minute: 0), false, false),
    ("2025-11-16T04:01:0Z", ReminderPart(weekDay: .Sunday, hour: 0, minute: 0), false, false),
])
func testScanWindows(timestamp: String, rt: ReminderPart, inScanWindow: Bool, inLateWindow: Bool) {
    let referenceDate = ISO8601DateFormatter().date(from: timestamp)!;
    var cal = Calendar(identifier: .gregorian)
    
    cal.timeZone = .gmt;
    #expect(rt.inScanWindow(asOf: referenceDate, calendar: cal) == inScanWindow)
    #expect(rt.inLateWindow(asOf: referenceDate, calendar: cal) == inLateWindow)
}
