import AppTypes
import ComposableArchitecture
import Dao
import DependenciesTestSupport
import Foundation
import Testing

@testable import EditSettingsNew_TopLevel

@MainActor
@Suite("SettingsResolver Feature Tests", .dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
    $0.uuid = .incrementing
    $0.date = .constant(Date(timeIntervalSince1970: 0))
})
struct SettingsResolverTests {

    @Test("start reconciles the current album descriptor into a cached id")
    func startResolvesAlbum() async {
        let store = TestStore(initialState: SettingsResolverFeature.State()) {
            SettingsResolverFeature()
        } withDependencies: {
            $0.photoKitAlbums.libraryAccess = { .authorized }
            $0.photoKitAlbums.findAlbum = { descriptor in
                descriptor == "Wall Photos" ? AlbumLocalId("local-123") : nil
            }
            $0.calendarAsync.calendarAccess = { .notDetermined }
        }
        store.exhaustivity = .off

        store.state.$albumDescriptor.withLock { $0 = AlbumDescriptor("Wall Photos") }

        await store.send(.start)
        await store.receive(\._albumDescriptorChanged)
        await store.receive(\._setAlbum)
        #expect(store.state.selectedAlbum == AlbumLocalId("local-123"))

        await store.send(.stop)
        await store.finish()
    }

    @Test("album descriptor with no local match clears the stale cached id")
    func albumNoMatchClearsId() async {
        let store = TestStore(initialState: SettingsResolverFeature.State()) {
            SettingsResolverFeature()
        } withDependencies: {
            $0.photoKitAlbums.libraryAccess = { .authorized }
            $0.photoKitAlbums.findAlbum = { _ in nil }
        }
        store.state.$selectedAlbum.withLock { $0 = AlbumLocalId("stale-id") }

        await store.send(._albumDescriptorChanged(AlbumDescriptor("Renamed Album")))
        await store.receive(\._setAlbum) {
            $0.$selectedAlbum.withLock { $0 = nil }
        }
    }

    @Test("cached album id backfills an absent descriptor")
    func albumBackfill() async {
        let store = TestStore(initialState: SettingsResolverFeature.State()) {
            SettingsResolverFeature()
        } withDependencies: {
            $0.photoKitAlbums.libraryAccess = { .authorized }
            $0.photoKitAlbums.albumDescriptor = { albumId in
                albumId == AlbumLocalId("kiosk-album") ? AlbumDescriptor("Wall Photos") : nil
            }
        }
        store.state.$selectedAlbum.withLock { $0 = AlbumLocalId("kiosk-album") }

        await store.send(._albumDescriptorChanged(nil))
        await store.receive(\._setAlbumDescriptor) {
            $0.$albumDescriptor.withLock { $0 = AlbumDescriptor("Wall Photos") }
        }
    }

    @Test("unauthorized library never touches the cached id")
    func unauthorizedSkips() async {
        let store = TestStore(initialState: SettingsResolverFeature.State()) {
            SettingsResolverFeature()
        } withDependencies: {
            $0.photoKitAlbums.libraryAccess = { .denied }
        }
        store.state.$selectedAlbum.withLock { $0 = AlbumLocalId("keep-me") }

        await store.send(._albumDescriptorChanged(AlbumDescriptor("Elsewhere")))
        #expect(store.state.selectedAlbum == AlbumLocalId("keep-me"))
    }

    @Test("calendar descriptor resolves by title and source")
    func calendarResolves() async {
        let store = TestStore(initialState: SettingsResolverFeature.State()) {
            SettingsResolverFeature()
        } withDependencies: {
            $0.calendarAsync.calendarAccess = { .fullAccess }
            $0.calendarAsync.findCalendar = { descriptor in
                descriptor == CalendarDescriptor(title: "Family", sourceTitle: "iCloud")
                    ? CalendarId("local-cal") : nil
            }
        }

        await store.send(._calendarDescriptorChanged(CalendarDescriptor(title: "Family", sourceTitle: "iCloud")))
        await store.receive(\._setCalendar) {
            $0.$selectedCalendar.withLock { $0 = CalendarId("local-cal") }
        }
    }

    @Test("a synced None clears the cached calendar instead of backfilling")
    func calendarNoSelectionClears() async {
        let store = TestStore(initialState: SettingsResolverFeature.State()) {
            SettingsResolverFeature()
        } withDependencies: {
            $0.calendarAsync.calendarAccess = { .fullAccess }
        }
        store.state.$selectedCalendar.withLock { $0 = CalendarId("was-picked") }

        await store.send(._calendarDescriptorChanged(.noSelection))
        await store.receive(\._setCalendar) {
            $0.$selectedCalendar.withLock { $0 = nil }
        }
    }

    @Test("cached calendar id backfills an absent descriptor")
    func calendarBackfill() async {
        let store = TestStore(initialState: SettingsResolverFeature.State()) {
            SettingsResolverFeature()
        } withDependencies: {
            $0.calendarAsync.calendarAccess = { .fullAccess }
            $0.calendarAsync.calendarDescriptor = { calendarId in
                calendarId == CalendarId("kiosk-cal")
                    ? CalendarDescriptor(title: "Family", sourceTitle: "iCloud") : nil
            }
        }
        store.state.$selectedCalendar.withLock { $0 = CalendarId("kiosk-cal") }

        await store.send(._calendarDescriptorChanged(nil))
        await store.receive(\._setCalendarDescriptor) {
            $0.$calendarDescriptor.withLock {
                $0 = CalendarDescriptor(title: "Family", sourceTitle: "iCloud")
            }
        }
    }

    @Test("resolving to the already-cached id writes nothing")
    func equalIdNoWrite() async {
        let store = TestStore(initialState: SettingsResolverFeature.State()) {
            SettingsResolverFeature()
        } withDependencies: {
            $0.photoKitAlbums.libraryAccess = { .authorized }
            $0.photoKitAlbums.findAlbum = { _ in AlbumLocalId("same-id") }
        }
        store.state.$selectedAlbum.withLock { $0 = AlbumLocalId("same-id") }

        await store.send(._albumDescriptorChanged(AlbumDescriptor("Wall Photos")))
        // _setAlbum arrives but the state assertion block is empty: no change.
        await store.receive(\._setAlbum)
    }
}
