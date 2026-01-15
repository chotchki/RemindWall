//
//  AddReminderFeatureTests.swift
//  
//
//  Created by Tests on 1/12/26.
//

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
struct AddReminderFeatureTests {
    
    // MARK: - Cancel Button Tests
    
    @Test("Cancel button dismisses view")
    func cancelButtonDismisses() async throws {
        @Dependency(\.defaultDatabase) var defaultDatabase
        @Dependency(\.uuid) var uuid
        
        try await defaultDatabase.write { db in
            try db.seedSampleData()
        };
        
        let trackee = Trackee(id: Trackee.ID(uuid()), name: "Alice")
        var dismissCalled = false
        
        let store = TestStore(initialState: AddReminderFeature.State(trackee: trackee)) {
            AddReminderFeature()
        } withDependencies: {
            $0.dismiss = DismissEffect {
                dismissCalled = true
            }
        }
        
        await store.send(.cancelButtonTapped)
        
        #expect(dismissCalled)
    }
    
    // MARK: - Save Button Tests
    
    @Test("Save button creates reminder with modified time")
    func saveButtonCreatesReminderWithDefaults() async throws {
        @Dependency(\.defaultDatabase) var defaultDatabase
        @Dependency(\.uuid) var uuid
        
        try await defaultDatabase.write { db in
            try db.seedSampleData()
        };
        
        // Get a trackee so we can link okay
        let trackee = try! await defaultDatabase.read{ db in
            try! Trackee.all.fetchOne(db)!
        }
        
        var dismissCalled = false
        
        let store = TestStore(initialState: AddReminderFeature.State(trackee: trackee)) {
            AddReminderFeature()
        } withDependencies: {
            $0.dismiss = DismissEffect {
                dismissCalled = true
            }
        }
        
        // Use a default reminder part to compare against
        let rp = ReminderPart()
        
        await store.send(.saveButtonTapped)
        await store.finish()
        #expect(dismissCalled)
        
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
    
    @Test("Save button creates reminder with modified time")
    func saveButtonCreatesReminderWithModifiedTime() async throws {
        @Dependency(\.defaultDatabase) var defaultDatabase
        @Dependency(\.uuid) var uuid
        
        try await defaultDatabase.write { db in
            try db.seedSampleData()
        };
        
        // Get a trackee so we can link okay
        let trackee = try! await defaultDatabase.read{ db in
            try! Trackee.all.fetchOne(db)!
        }
        
        var dismissCalled = false
        
        let store = TestStore(initialState: AddReminderFeature.State(trackee: trackee)) {
            AddReminderFeature()
        } withDependencies: {
            $0.dismiss = DismissEffect {
                dismissCalled = true
            }
        }
        
        // Use a default reminder part to compare against
        var rp = ReminderPart()
        rp.hour += 1
        
        await store.send(.timePicker(.incrementHour)){
            $0.$reminderPart.withLock{
                $0.hour += 1
            }
        }
        
        await store.send(.saveButtonTapped)
        await store.finish()
        #expect(dismissCalled)
        
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
