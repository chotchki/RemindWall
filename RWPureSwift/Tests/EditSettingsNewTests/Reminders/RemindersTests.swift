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
        
        await store.send(.addButtonTapped)
        
        await store.send(.presented(.addReminder(.timePicker(.incrementHour)))){
            $0.presented.$reminderPart.withLock{
                $0.hour += 1
            }
        }
        
        await store.send(.presented(.addReminder(.saveButtonTapped)))
        await store.finish()
        
        // Get what was saved
        let savedReminder = try! await defaultDatabase.read{ db in
            try! ReminderTime.where{ $0.trackeeId == trackee.id}.fetchAll(db)
        }
        
        #expect(savedReminder.count == 1)
        #expect(savedReminder.first?.trackeeId == trackee.id)
        #expect(savedReminder.first?.weekDay == rp.weekDay.rawValue)
        #expect(savedReminder.first?.hour == rp.hour)
        #expect(savedReminder.first?.minute == rp.minute)
        #expect(savedReminder.first?.associatedTag == "")
        #expect(savedReminder.first?.lastScan == nil)
    }
}
