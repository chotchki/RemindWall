import DataModel
import XCTest


final class ReminderTimeTests: XCTestCase {
    private let c = Calendar.current
    
    func testConvertToRT1() throws {
        var dateComponents = DateComponents()
            dateComponents.year = 2024
            dateComponents.month = 1
            dateComponents.day = 6
            dateComponents.hour = 0
            dateComponents.minute = 0
            
        let date = c.date(from: dateComponents)!
        
        let target = ReminderTime(weekDay: 7, hour: 0, minute: 0)
        
        XCTAssertEqual(target, ReminderTime(date: date, calendar: c))
    }
    
    func testConvertToRT2() throws {
        var dateComponents = DateComponents()
            dateComponents.year = 2024
            dateComponents.month = 1
            dateComponents.day = 7
            dateComponents.hour = 0
            dateComponents.minute = 0
            
        let date = c.date(from: dateComponents)!
        
        let target = ReminderTime(weekDay: 1, hour: 0, minute: 0)
        
        XCTAssertEqual(target, ReminderTime(date: date, calendar: c))
    }
    
    func testEarlyRT() throws {
        let rt1 = ReminderTime(weekDay: 1, hour: 1, minute: 2)
        XCTAssertEqual(rt1.earlyScan(), ReminderTime(weekDay: 7, hour: 23, minute: 2))
        
        let rt2 = ReminderTime(weekDay: 5, hour: 23, minute: 2)
        XCTAssertEqual(rt2.earlyScan(), ReminderTime(weekDay: 5, hour: 21, minute: 2))
    }
    
    func testLateRT() throws {
        let rt1 = ReminderTime(weekDay: 1, hour: 1, minute: 2)
        XCTAssertEqual(rt1.lateReminder(), ReminderTime(weekDay: 1, hour: 5, minute: 2))
        
        let rt2 = ReminderTime(weekDay: 7, hour: 23, minute: 2)
        XCTAssertEqual(rt2.lateReminder(), ReminderTime(weekDay: 1, hour: 3, minute: 2))
    }
    
    func testNotLateBefore() throws {
        let rt = ReminderTime(weekDay: 1, hour: 1, minute: 1)
        
        var dateComponents = DateComponents()
            dateComponents.year = 2024
            dateComponents.month = 1
            dateComponents.day = 1
            dateComponents.hour = 0
            
        let date = c.date(from: dateComponents)!
        
        XCTAssertFalse(rt.inLateWindow(asOf: date, calendar: c))
    }
    
    func testNotLateAfter() throws {
        let rt = ReminderTime(weekDay: 1, hour: 4, minute: 1)
        
        var dateComponents = DateComponents()
            dateComponents.year = 2024
            dateComponents.month = 1
            dateComponents.day = 1
            dateComponents.hour = 0
            
        let date = c.date(from: dateComponents)!
        
        XCTAssertFalse(rt.inLateWindow(asOf: date, calendar: c))
        XCTAssertFalse(rt.inScanWindow(asOf: date, calendar: c))
    }
    
    func testLate() throws {
        let rt = ReminderTime(weekDay: 2, hour: 1, minute: 1)
        
        var dateComponents = DateComponents()
            dateComponents.year = 2024
            dateComponents.month = 1
            dateComponents.day = 1
            dateComponents.hour = 2
            
        let date = c.date(from: dateComponents)!
        
        XCTAssertTrue(rt.inLateWindow(asOf: date, calendar: c))
        XCTAssertTrue(rt.inScanWindow(asOf: date, calendar: c))
    }

    func testNotScanBefore() throws {
        let rt = ReminderTime(weekDay: 2, hour: 1, minute: 1)
        
        var dateComponents = DateComponents()
            dateComponents.year = 2023
            dateComponents.month = 12
            dateComponents.day = 31
            dateComponents.hour = 22
            
        let date = c.date(from: dateComponents)!
        
        XCTAssertFalse(rt.inScanWindow(asOf: date, calendar: c))
    }
    
    func testScan() throws {
        let rt = ReminderTime(weekDay: 2, hour: 1, minute: 1)
        
        var dateComponents = DateComponents()
            dateComponents.year = 2023
            dateComponents.month = 12
            dateComponents.day = 31
            dateComponents.hour = 23
            dateComponents.minute = 2
            
        let date = c.date(from: dateComponents)!
        
        XCTAssertTrue(rt.inScanWindow(asOf: date, calendar: c))
    }
    
    func testNotScanAfter() throws {
        let rt = ReminderTime(weekDay: 2, hour: 1, minute: 1)
        
        var dateComponents = DateComponents()
            dateComponents.year = 2024
            dateComponents.month = 1
            dateComponents.day = 1
            dateComponents.hour = 5
            dateComponents.minute = 2
            
        let date = c.date(from: dateComponents)!
        
        XCTAssertFalse(rt.inScanWindow(asOf: date, calendar: c))
    }
}
