import AppTypes
import ComposableArchitecture
import Dao
import DependenciesTestSupport
import Testing

@testable import EditSettingsNew_Trackees

@MainActor
@Suite("TrackeeDetail Feature Tests", .dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
    $0.uuid = .incrementing
})
struct TrackeeDetailTests {

    @Test("deleteButtonTapped shows confirmation alert")
    func deleteButtonShowsAlert() async {
        @Dependency(\.defaultDatabase) var defaultDatabase
        let trackee = try! await defaultDatabase.read { db in
            try! Trackee.all.fetchOne(db)!
        }

        let store = TestStore(
            initialState: TrackeeDetailFeature.State(trackee: trackee)
        ) {
            TrackeeDetailFeature()
        }

        await store.send(.deleteButtonTapped) {
            $0.alert = .confirmDeletion(name: trackee.name)
        }
    }

    @Test("alert confirmDeletion sends delegate and dismisses")
    func alertConfirmDeletion() async {
        @Dependency(\.defaultDatabase) var defaultDatabase
        let trackee = try! await defaultDatabase.read { db in
            try! Trackee.all.fetchOne(db)!
        }

        var delegateReceived = false

        let store = TestStore(
            initialState: TrackeeDetailFeature.State(trackee: trackee)
        ) {
            TrackeeDetailFeature()
        } withDependencies: {
            $0.dismiss = DismissEffect {}
        }

        store.exhaustivity = .off

        await store.send(.deleteButtonTapped) {
            $0.alert = .confirmDeletion(name: trackee.name)
        }

        await store.send(.alert(.presented(.confirmDeletion))) {
            $0.alert = nil
        }

        await store.skipReceivedActions()
    }

    @Test("alert dismiss does not trigger deletion")
    func alertDismiss() async {
        @Dependency(\.defaultDatabase) var defaultDatabase
        let trackee = try! await defaultDatabase.read { db in
            try! Trackee.all.fetchOne(db)!
        }

        let store = TestStore(
            initialState: TrackeeDetailFeature.State(trackee: trackee)
        ) {
            TrackeeDetailFeature()
        }

        await store.send(.deleteButtonTapped) {
            $0.alert = .confirmDeletion(name: trackee.name)
        }

        await store.send(.alert(.dismiss)) {
            $0.alert = nil
        }
    }

    @Test("delegate action does not cause side effects")
    func delegateNoSideEffects() async {
        @Dependency(\.defaultDatabase) var defaultDatabase
        let trackee = try! await defaultDatabase.read { db in
            try! Trackee.all.fetchOne(db)!
        }

        let store = TestStore(
            initialState: TrackeeDetailFeature.State(trackee: trackee)
        ) {
            TrackeeDetailFeature()
        }

        await store.send(.delegate(.confirmDeletion))
    }

    @Test("remindersFeature action is forwarded")
    func remindersActionForwarded() async {
        @Dependency(\.defaultDatabase) var defaultDatabase
        let trackee = try! await defaultDatabase.read { db in
            try! Trackee.all.fetchOne(db)!
        }

        let store = TestStore(
            initialState: TrackeeDetailFeature.State(trackee: trackee)
        ) {
            TrackeeDetailFeature()
        }

        store.exhaustivity = .off

        await store.send(.remindersFeature(.addReminderButtonTapped))
    }

    @Test("setRemindersEnabled updates state and persists to the database")
    func setRemindersEnabledPersists() async {
        @Dependency(\.defaultDatabase) var defaultDatabase
        let trackee = try! await defaultDatabase.read { db in
            try! Trackee.all.fetchOne(db)!
        }
        // Seed trackees start enabled — the toggle has somewhere to move.
        #expect(trackee.remindersEnabled == true)

        let store = TestStore(
            initialState: TrackeeDetailFeature.State(trackee: trackee)
        ) {
            TrackeeDetailFeature()
        }

        await store.send(.setRemindersEnabled(false)) {
            $0.trackee.remindersEnabled = false
        }
        await store.finish()

        let persisted = try! await defaultDatabase.read { db in
            try! Trackee.find(trackee.id).fetchOne(db)
        }
        #expect(persisted?.remindersEnabled == false)
    }

    @Test("setRemindersEnabled(true) re-enables a paused trackee and persists")
    func setRemindersEnabledReenables() async {
        @Dependency(\.defaultDatabase) var defaultDatabase
        let seeded = try! await defaultDatabase.read { db in
            try! Trackee.all.fetchOne(db)!
        }
        // Start from the paused state in the DB.
        try! await defaultDatabase.write { db in
            try Trackee.find(seeded.id)
                .update { $0.remindersEnabled = false }
                .execute(db)
        }
        let paused = try! await defaultDatabase.read { db in
            try! Trackee.find(seeded.id).fetchOne(db)!
        }
        #expect(paused.remindersEnabled == false)

        let store = TestStore(
            initialState: TrackeeDetailFeature.State(trackee: paused)
        ) {
            TrackeeDetailFeature()
        }

        await store.send(.setRemindersEnabled(true)) {
            $0.trackee.remindersEnabled = true
        }
        await store.finish()

        let persisted = try! await defaultDatabase.read { db in
            try! Trackee.find(seeded.id).fetchOne(db)
        }
        #expect(persisted?.remindersEnabled == true)
    }

    @Test("state initializes with trackee and nil alert")
    func stateInitializes() async {
        @Dependency(\.defaultDatabase) var defaultDatabase
        let trackee = try! await defaultDatabase.read { db in
            try! Trackee.all.fetchOne(db)!
        }

        let state = TrackeeDetailFeature.State(trackee: trackee)
        #expect(state.trackee == trackee)
        #expect(state.alert == nil)
    }
}
