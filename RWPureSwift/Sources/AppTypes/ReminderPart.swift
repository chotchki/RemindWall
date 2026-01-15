import Foundation
import SwiftData

public enum DaysOfWeek: Int, CaseIterable, Sendable {
    case Sunday = 1,
        Monday,
        Tuesday,
        Wednesday,
        Thursday,
        Friday,
        Saturday
}

public struct ReminderPart: Equatable, Sendable {
    //Range 1 = Sun to 7 = Sat
    public var weekDay: DaysOfWeek
    public var hour: Int
    public var minute: Int
    
    public init(){
        self.weekDay = .Sunday
        self.hour = 1
        self.minute = 0
    }
    
    public init(weekDay: DaysOfWeek, hour: Int, minute: Int) {
        self.weekDay = weekDay
        self.hour = hour
        self.minute = minute
    }
    
    public init(date: Date, calendar: Calendar){
        self.weekDay = DaysOfWeek(rawValue: calendar.component(.weekday, from: date))!
        self.hour = calendar.component(.hour, from: date)
        self.minute = calendar.component(.minute, from: date)
    }
    
    public func earlyScan() -> ReminderPart {
        var newWeekDay = weekDay.rawValue
        
        //2 hours before
        var newHour = hour - 2
        if newHour < 0 {
            newHour = 24 + newHour
            newWeekDay = newWeekDay - 1
        }
        if newWeekDay < 1 {
            newWeekDay = 7 + newWeekDay
        }
        
        return ReminderPart(weekDay: DaysOfWeek(rawValue:newWeekDay)!, hour: newHour, minute: minute)
    }
    
    public func lateReminder() -> ReminderPart {
        var newWeekDay = weekDay.rawValue
        
        //4 hours after
        var newHour = hour + 4
        if newHour > 23 {
            newHour -= 24
            newWeekDay += 1
        }
        
        if newWeekDay > 7 {
            newWeekDay -= 7
        }
        
        return ReminderPart(weekDay: DaysOfWeek(rawValue:newWeekDay)!, hour: newHour, minute: minute)
    }
    
    /// By default a reminder is late if we are within 4 hours after its window
    public func inLateWindow(asOf: Date, calendar: Calendar) -> Bool {
        let now_rt = ReminderPart(date: asOf, calendar: calendar)
        
        let late_rt = self.lateReminder()
        
        //Have to be on the same days for this to even be close
        if now_rt.weekDay != self.weekDay && now_rt.weekDay != late_rt.weekDay {
            
            return false
        }
        
        //Are we in the right hour range?
        if now_rt.weekDay == self.weekDay && now_rt.hour < self.hour {
            return false
        }
        
        if now_rt.weekDay == late_rt.weekDay && now_rt.hour > late_rt.hour {
            return false
        }
        
        //Are we in the minute range?
        if now_rt.weekDay == self.weekDay && now_rt.hour == self.hour && now_rt.minute < self.minute {
            return false
        }
        
        if now_rt.weekDay == late_rt.weekDay && now_rt.hour == late_rt.hour && now_rt.minute >= late_rt.minute {
            return false
        }
        
        return true
    }
    
    /// By default a reminder scan window is two hours before OR in the late window
    public func inScanWindow(asOf: Date, calendar: Calendar) -> Bool {
        if self.inLateWindow(asOf: asOf, calendar: calendar){
            return true
        }
        
        //Now we just have to check for early
        let now_rt = ReminderPart(date: asOf, calendar: calendar)
        
        let early_rt = self.earlyScan()
        
        //Have to be on the same days for this to even be close
        if now_rt.weekDay != self.weekDay && now_rt.weekDay != early_rt.weekDay {
            return false
        }
        
        //Are we in the right hour range?
        if now_rt.weekDay == early_rt.weekDay && now_rt.hour < early_rt.hour {
            return false
        }
        
        if now_rt.weekDay == self.weekDay && now_rt.hour > self.hour {
            return false
        }
        
        //Are we in the minute range?
        if now_rt.weekDay == early_rt.weekDay && now_rt.hour == early_rt.hour && now_rt.minute < early_rt.minute {
            return false
        }
        
        if now_rt.weekDay == self.weekDay && now_rt.hour == self.hour && now_rt.minute > self.minute {
            return false
        }
        
        return true
    }
}

extension ReminderPart: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "ReminderPart(weekDay: \(weekDay), hour: \(hour), minute: \(minute)"
    }
}
