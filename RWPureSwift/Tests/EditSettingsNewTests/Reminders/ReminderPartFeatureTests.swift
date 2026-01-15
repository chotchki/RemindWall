//
//  ReminderPartFeatureTests.swift
//  
//
//  Created by Tests on 1/11/26.
//

import AppTypes
import ComposableArchitecture
import Testing

@testable import EditSettingsNew_Reminders

@MainActor
@Suite("ReminderPart Feature Tests")
struct ReminderPartFeatureTests {
    
    // MARK: - Hour Tests
    
    @Test("Increment hour wraps from 23 to 0")
    func incrementHourWrapsAround() async {
        let reminderPart = Shared(value: ReminderPart(weekDay: .Monday, hour: 23, minute: 30))
        let store = TestStore(initialState: ReminderPartFeature.State(reminderPart)) {
            ReminderPartFeature()
        }
        
        await store.send(.incrementHour) {
            $0.$reminderPart.hour.withLock { $0 = 0 }
        }
        
        #expect(store.state.reminderPart.hour == 0)
    }
    
    @Test("Increment hour increases by 1")
    func incrementHourIncreasesValue() async {
        let reminderPart = Shared(value: ReminderPart(weekDay: .Monday, hour: 10, minute: 30))
        let store = TestStore(initialState: ReminderPartFeature.State(reminderPart)) {
            ReminderPartFeature()
        }
        
        await store.send(.incrementHour) {
            $0.$reminderPart.hour.withLock { $0 = 11 }
        }
        
        #expect(store.state.reminderPart.hour == 11)
    }
    
    @Test("Decrement hour wraps from 0 to 23")
    func decrementHourWrapsAround() async {
        let reminderPart = Shared(value: ReminderPart(weekDay: .Monday, hour: 0, minute: 30))
        let store = TestStore(initialState: ReminderPartFeature.State(reminderPart)) {
            ReminderPartFeature()
        }
        
        await store.send(.decrementHour) {
            $0.$reminderPart.hour.withLock { $0 = 23 }
        }
        
        #expect(store.state.reminderPart.hour == 23)
    }
    
    @Test("Decrement hour decreases by 1")
    func decrementHourDecreasesValue() async {
        let reminderPart = Shared(value: ReminderPart(weekDay: .Monday, hour: 10, minute: 30))
        let store = TestStore(initialState: ReminderPartFeature.State(reminderPart)) {
            ReminderPartFeature()
        }
        
        await store.send(.decrementHour) {
            $0.$reminderPart.hour.withLock { $0 = 9 }
        }
        
        #expect(store.state.reminderPart.hour == 9)
    }
    
    // MARK: - Minute Tests
    
    @Test("Increment minute wraps from 59 to 0")
    func incrementMinuteWrapsAround() async {
        let reminderPart = Shared(value: ReminderPart(weekDay: .Monday, hour: 10, minute: 59))
        let store = TestStore(initialState: ReminderPartFeature.State(reminderPart)) {
            ReminderPartFeature()
        }
        
        await store.send(.incrementMinute) {
            $0.$reminderPart.minute.withLock { $0 = 0 }
        }
        
        #expect(store.state.reminderPart.minute == 0)
    }
    
    @Test("Increment minute increases by 1")
    func incrementMinuteIncreasesValue() async {
        let reminderPart = Shared(value: ReminderPart(weekDay: .Monday, hour: 10, minute: 30))
        let store = TestStore(initialState: ReminderPartFeature.State(reminderPart)) {
            ReminderPartFeature()
        }
        
        await store.send(.incrementMinute) {
            $0.$reminderPart.minute.withLock { $0 = 31 }
        }
        
        #expect(store.state.reminderPart.minute == 31)
    }
    
    @Test("Decrement minute wraps from 0 to 59")
    func decrementMinuteWrapsAround() async {
        let reminderPart = Shared(value: ReminderPart(weekDay: .Monday, hour: 10, minute: 0))
        let store = TestStore(initialState: ReminderPartFeature.State(reminderPart)) {
            ReminderPartFeature()
        }
        
        await store.send(.decrementMinute) {
            $0.$reminderPart.minute.withLock { $0 = 59 }
        }
        
        #expect(store.state.reminderPart.minute == 59)
    }
    
    @Test("Decrement minute decreases by 1")
    func decrementMinuteDecreasesValue() async {
        let reminderPart = Shared(value: ReminderPart(weekDay: .Monday, hour: 10, minute: 30))
        let store = TestStore(initialState: ReminderPartFeature.State(reminderPart)) {
            ReminderPartFeature()
        }
        
        await store.send(.decrementMinute) {
            $0.$reminderPart.minute.withLock { $0 = 29 }
        }
        
        #expect(store.state.reminderPart.minute == 29)
    }
    
    // MARK: - AM/PM Toggle Tests
    
    @Test("Toggle AM to PM adds 12 hours")
    func toggleAMtoPM() async {
        let reminderPart = Shared(value: ReminderPart(weekDay: .Monday, hour: 8, minute: 30))
        let store = TestStore(initialState: ReminderPartFeature.State(reminderPart)) {
            ReminderPartFeature()
        }
        
        // Verify we're starting in AM
        #expect(store.state.isAM == true)
        
        await store.send(.toggleAMPM) {
            $0.$reminderPart.hour.withLock { $0 = 20 }
        }
        
        #expect(store.state.reminderPart.hour == 20)
        #expect(store.state.isAM == false)
    }
    
    @Test("Toggle PM to AM subtracts 12 hours")
    func togglePMtoAM() async {
        let reminderPart = Shared(value: ReminderPart(weekDay: .Monday, hour: 20, minute: 30))
        let store = TestStore(initialState: ReminderPartFeature.State(reminderPart)) {
            ReminderPartFeature()
        }
        
        // Verify we're starting in PM
        #expect(store.state.isAM == false)
        
        await store.send(.toggleAMPM) {
            $0.$reminderPart.hour.withLock { $0 = 8 }
        }
        
        #expect(store.state.reminderPart.hour == 8)
        #expect(store.state.isAM == true)
    }
    
    @Test("Toggle at midnight (hour 0) switches to noon (hour 12)")
    func toggleMidnightToNoon() async {
        let reminderPart = Shared(value: ReminderPart(weekDay: .Monday, hour: 0, minute: 30))
        let store = TestStore(initialState: ReminderPartFeature.State(reminderPart)) {
            ReminderPartFeature()
        }
        
        #expect(store.state.isAM == true)
        
        await store.send(.toggleAMPM) {
            $0.$reminderPart.hour.withLock { $0 = 12 }
        }
        
        #expect(store.state.reminderPart.hour == 12)
        #expect(store.state.isAM == false)
    }
    
    @Test("Toggle at noon (hour 12) switches to midnight (hour 0)")
    func toggleNoonToMidnight() async {
        let reminderPart = Shared(value: ReminderPart(weekDay: .Monday, hour: 12, minute: 30))
        let store = TestStore(initialState: ReminderPartFeature.State(reminderPart)) {
            ReminderPartFeature()
        }
        
        #expect(store.state.isAM == false)
        
        await store.send(.toggleAMPM) {
            $0.$reminderPart.hour.withLock { $0 = 0 }
        }
        
        #expect(store.state.reminderPart.hour == 0)
        #expect(store.state.isAM == true)
    }
    
    // MARK: - Week Day Tests
    
    @Test("Set weekday to Sunday")
    func setWeekDaySunday() async {
        let reminderPart = Shared(value: ReminderPart(weekDay: .Monday, hour: 10, minute: 30))
        let store = TestStore(initialState: ReminderPartFeature.State(reminderPart)) {
            ReminderPartFeature()
        }
        
        await store.send(.setWeekDay(.Sunday)) {
            $0.$reminderPart.weekDay.withLock { $0 = .Sunday }
        }
        
        #expect(store.state.reminderPart.weekDay == .Sunday)
    }
    
    @Test("Set weekday changes correctly")
    func setWeekDayChanges() async {
        let reminderPart = Shared(value: ReminderPart(weekDay: .Monday, hour: 10, minute: 30))
        let store = TestStore(initialState: ReminderPartFeature.State(reminderPart)) {
            ReminderPartFeature()
        }
        
        for day in DaysOfWeek.allCases {
            await store.send(.setWeekDay(day)) {
                $0.$reminderPart.weekDay.withLock { $0 = day }
            }
            
            #expect(store.state.reminderPart.weekDay == day)
        }
    }
    
    // MARK: - Display Hour Tests
    
    @Test("Display hour shows 12 for hour 0 (midnight)")
    func displayHourMidnight() async {
        let reminderPart = Shared(value: ReminderPart(weekDay: .Monday, hour: 0, minute: 30))
        let store = TestStore(initialState: ReminderPartFeature.State(reminderPart)) {
            ReminderPartFeature()
        }
        
        #expect(store.state.displayHour == 12)
    }
    
    @Test("Display hour shows 12 for hour 12 (noon)")
    func displayHourNoon() async {
        let reminderPart = Shared(value: ReminderPart(weekDay: .Monday, hour: 12, minute: 30))
        let store = TestStore(initialState: ReminderPartFeature.State(reminderPart)) {
            ReminderPartFeature()
        }
        
        #expect(store.state.displayHour == 12)
    }
    
    @Test("Display hour converts 24-hour to 12-hour format correctly")
    func displayHour12HourConversion() async {
        let testCases: [(hour24: Int, expected12: Int)] = [
            (0, 12),   // 12 AM
            (1, 1),    // 1 AM
            (11, 11),  // 11 AM
            (12, 12),  // 12 PM
            (13, 1),   // 1 PM
            (23, 11)   // 11 PM
        ]
        
        for testCase in testCases {
            let reminderPart = Shared(value: ReminderPart(weekDay: .Monday, hour: testCase.hour24, minute: 0))
            let store = TestStore(initialState: ReminderPartFeature.State(reminderPart)) {
                ReminderPartFeature()
            }
            
            #expect(store.state.displayHour == testCase.expected12,
                   "Hour \(testCase.hour24) should display as \(testCase.expected12)")
        }
    }
    
    // MARK: - Combined Action Tests
    
    @Test("Multiple hour increments work correctly")
    func multipleHourIncrements() async {
        let reminderPart = Shared(value: ReminderPart(weekDay: .Monday, hour: 22, minute: 30))
        let store = TestStore(initialState: ReminderPartFeature.State(reminderPart)) {
            ReminderPartFeature()
        }
        
        await store.send(.incrementHour) { $0.$reminderPart.hour.withLock { $0 = 23 } }
        await store.send(.incrementHour) { $0.$reminderPart.hour.withLock { $0 = 0 } }
        await store.send(.incrementHour) { $0.$reminderPart.hour.withLock { $0 = 1 } }
        
        #expect(store.state.reminderPart.hour == 1)
    }
    
    @Test("Multiple minute increments work correctly")
    func multipleMinuteIncrements() async {
        let reminderPart = Shared(value: ReminderPart(weekDay: .Monday, hour: 10, minute: 58))
        let store = TestStore(initialState: ReminderPartFeature.State(reminderPart)) {
            ReminderPartFeature()
        }
        
        await store.send(.incrementMinute) { $0.$reminderPart.minute.withLock { $0 = 59 } }
        await store.send(.incrementMinute) { $0.$reminderPart.minute.withLock { $0 = 0 } }
        await store.send(.incrementMinute) { $0.$reminderPart.minute.withLock { $0 = 1 } }
        
        #expect(store.state.reminderPart.minute == 1)
    }
    
    @Test("Changing time and weekday together")
    func combinedTimeAndWeekdayChanges() async {
        let reminderPart = Shared(value: ReminderPart(weekDay: .Monday, hour: 8, minute: 30))
        let store = TestStore(initialState: ReminderPartFeature.State(reminderPart)) {
            ReminderPartFeature()
        }
        
        await store.send(.setWeekDay(.Friday)) {
            $0.$reminderPart.weekDay.withLock { $0 = .Friday }
        }
        
        await store.send(.incrementHour) {
            $0.$reminderPart.hour.withLock { $0 = 9 }
        }
        
        await store.send(.incrementMinute) {
            $0.$reminderPart.minute.withLock { $0 = 31 }
        }
        
        await store.send(.toggleAMPM) {
            $0.$reminderPart.hour.withLock { $0 = 21 }
        }
        
        #expect(store.state.reminderPart.weekDay == .Friday)
        #expect(store.state.reminderPart.hour == 21)
        #expect(store.state.reminderPart.minute == 31)
        #expect(store.state.isAM == false)
        #expect(store.state.displayHour == 9)
    }
}
