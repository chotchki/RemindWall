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
    }


}
