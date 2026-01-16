//
//  AddReminderFeatureTests.swift
//  
//
//  Created by Tests on 1/12/26.
//

import ComposableArchitecture
import Dao
import DependenciesTestSupport
import SQLiteData
import Testing


@testable import EditSettingsNew_Reminders

@MainActor
@Suite(.dependencies {
    $0.uuid = .incrementing
  })
struct AddReminderFeatureTests {
    
    // MARK: - Cancel Button Tests
    
    @Test("Cancel button dismisses view")
    func cancelButtonDismisses() async throws {
        @Dependency(\.uuid) var uuid

        
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
}
