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
            $0.alert = .confirmDeletion
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
            $0.alert = .confirmDeletion
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
            $0.alert = .confirmDeletion
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
