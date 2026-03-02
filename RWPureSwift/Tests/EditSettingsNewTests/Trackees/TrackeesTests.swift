import ComposableArchitecture
import Dao
import DependenciesTestSupport
import SQLiteData
import Testing

@testable import EditSettingsNew_Trackees

@MainActor
@Suite("Trackees Feature Tests", .dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
    $0.uuid = .incrementing
})
struct TrackeesFeatureTests {

    @Test("addButtonTapped presents add trackee sheet")
    func addButtonTapped() async {
        let store = TestStore(initialState: TrackeesFeature.State()) {
            TrackeesFeature()
        }

        store.exhaustivity = .off

        await store.send(.addButtonTapped)

        // Verify destination was set
        #expect(store.state.destination != nil)
        if case .addTrackee(let addState) = store.state.destination {
            #expect(addState.trackee.name == "")
        } else {
            Issue.record("Expected addTrackee destination")
        }
    }

    @Test("destination dismiss clears destination")
    func destinationDismiss() async {
        @Dependency(\.uuid) var uuid

        var state = TrackeesFeature.State()
        state.destination = .addTrackee(
            AddTrackeeFeature.State(
                trackee: Trackee(id: Trackee.ID(uuid()), name: "Test")
            )
        )

        let store = TestStore(initialState: state) {
            TrackeesFeature()
        }

        await store.send(.destination(.dismiss)) {
            $0.destination = nil
        }
    }

    @Test("save trackee from add sheet writes to database")
    func saveTrackeeFromAddSheet() async {
        @Dependency(\.uuid) var uuid
        @Dependency(\.defaultDatabase) var defaultDatabase

        let trackeeId = Trackee.ID(uuid())
        let newTrackee = Trackee(id: trackeeId, name: "New Person")

        // Set up state with the destination already presented
        var state = TrackeesFeature.State()
        state.destination = .addTrackee(
            AddTrackeeFeature.State(trackee: newTrackee)
        )

        let store = TestStore(initialState: state) {
            TrackeesFeature()
        }

        store.exhaustivity = .off

        await store.send(
            .destination(
                .presented(
                    .addTrackee(.delegate(.saveTrackee(newTrackee)))
                )
            )
        )

        await store.finish()

        // Verify the trackee was written to the database
        let saved = try! await defaultDatabase.read { db in
            try! Trackee.find(trackeeId).fetchOne(db)
        }
        #expect(saved != nil)
        #expect(saved?.name == "New Person")
    }

    @Test("initial state has no destination and empty path")
    func initialState() async {
        let state = TrackeesFeature.State()
        #expect(state.destination == nil)
        #expect(state.path.count == 0)
    }
}
