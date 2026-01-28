import AppTypes
import ComposableArchitecture
import Dao
import DependenciesTestSupport
import SQLiteData
import Testing


@testable import EditSettingsNew_Reminders

@MainActor
@Suite(.dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
    $0.uuid = .incrementing
  })
struct RemindersFeatureTests {
    @Test("Create Reminder, save it, delete it")
    func fullLifeCycle() async throws {
        @Dependency(\.defaultDatabase) var defaultDatabase
        @Dependency(\.uuid) var uuid
        
        // Get a trackee so we can link okay
        let trackee = try! await defaultDatabase.read{ db in
            try! Trackee.all.fetchOne(db)!
        }
        
        let store = TestStore(initialState: RemindersFeature.State(trackee: trackee)) {
            RemindersFeature()
        } withDependencies: {
            $0.dismiss = DismissEffect {}
        }
        
        // Tap the add button
        await store.send(.addReminderButtonTapped) {
            $0.destination = .addReminder(AddReminderFeature.State(trackee: trackee))
        }
        
        // Increment the hour in the time picker
        await store.send(.destination(.presented(.addReminder(.timePicker(.incrementHour))))) {
            $0.destination?.addReminder?.$reminderPart.withLock {
                $0.hour += 1
            }
        }
        
        // Save the reminder
        await store.send(.destination(.presented(.addReminder(.saveButtonTapped))))
        
        // Wait for the delegate action to propagate
        await store.receive(\.destination.presented.addReminder.delegate.saveReminder)
        
        await store.receive(\.destination.dismiss){
            $0.destination = nil
        }
        
        await store.finish()
        
        // Get what was saved
        let savedReminders = try! await defaultDatabase.read { db in
            try! ReminderTime.where { $0.trackeeId == trackee.id }.fetchAll(db)
        }
        
        #expect(savedReminders.count == 1)
        
        if let savedReminder = savedReminders.first {
            #expect(savedReminder.trackeeId == trackee.id)
            #expect(savedReminder.weekDay == DaysOfWeek.Sunday.rawValue)
            #expect(savedReminder.hour == 2) // Started at 1, incremented by 1
            #expect(savedReminder.minute == 0)
            #expect(savedReminder.associatedTag == "")
            #expect(savedReminder.lastScan == nil)
        }
    }
}
