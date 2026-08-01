import AppTypes
import CalendarAsync
import ComposableArchitecture
import Dao
import DependenciesTestSupport
@preconcurrency import EventKit
import Foundation
import Testing

@testable import EditSettingsNew_TopLevel

@MainActor
@Suite("CalendarPicker Feature Tests", .dependencies {
    // .syncedSetting backs the calendar descriptor: reads the database at
    // State init, stamps lastModified on descriptor writes.
    $0.defaultDatabase = try! $0.appDatabase()
    $0.uuid = .incrementing
    $0.date = .constant(Date(timeIntervalSince1970: 0))
})
struct CalendarPickerTests {

    @Test("onAppear when not authorized shows authorize button state")
    func onAppearNotAuthorized() async {
        let store = TestStore(initialState: CalendarPickerFeature.State()) {
            CalendarPickerFeature()
        } withDependencies: {
            $0.calendarAsync.calendarAccess = { .notDetermined }
            $0.calendarAsync.getCalendars = { [] }
        }

        await store.send(.onAppear)
    }

    @Test("onAppear when denied shows denied state")
    func onAppearDenied() async {
        let store = TestStore(initialState: CalendarPickerFeature.State()) {
            CalendarPickerFeature()
        } withDependencies: {
            $0.calendarAsync.calendarAccess = { .denied }
            $0.calendarAsync.getCalendars = { [] }
        }

        await store.send(.onAppear) {
            $0.calendarStatus = .denied
        }
    }

    @Test("onAppear when authorized loads calendars")
    func onAppearAuthorized() async {
        let store = TestStore(initialState: CalendarPickerFeature.State()) {
            CalendarPickerFeature()
        } withDependencies: {
            $0.calendarAsync.calendarAccess = { .fullAccess }
            $0.calendarAsync.getCalendars = { [] }
        }

        await store.send(.onAppear) {
            $0.calendarStatus = .fullAccess
        }

        await store.receive(\.loadListComplete)
    }

    @Test("tapAuthorizeAccess requests access and loads calendars on success")
    func tapAuthorizeAccessGranted() async {
        let store = TestStore(initialState: CalendarPickerFeature.State()) {
            CalendarPickerFeature()
        } withDependencies: {
            $0.calendarAsync.calendarAccess = { .fullAccess }
            $0.calendarAsync.requestAccess = { true }
            $0.calendarAsync.getCalendars = { [] }
        }

        await store.send(.tapAuthorizeAccess)

        await store.receive(\.authorizationComplete) {
            $0.calendarStatus = .fullAccess
        }

        await store.receive(\.loadListComplete)
    }

    @Test("tapAuthorizeAccess does not load calendars when denied")
    func tapAuthorizeAccessDenied() async {
        let store = TestStore(initialState: CalendarPickerFeature.State()) {
            CalendarPickerFeature()
        } withDependencies: {
            $0.calendarAsync.calendarAccess = { .denied }
            $0.calendarAsync.requestAccess = { false }
        }

        await store.send(.tapAuthorizeAccess)

        await store.receive(\.authorizationComplete) {
            $0.calendarStatus = .denied
        }
    }

    @Test("loadListComplete sets available calendars")
    func loadListCompleteSetsCalendars() async {
        var state = CalendarPickerFeature.State()
        state.calendarStatus = .fullAccess

        let store = TestStore(initialState: state) {
            CalendarPickerFeature()
        }

        await store.send(.loadListComplete(nil))
    }

    @Test("tapOpenSettings does not change state")
    func tapOpenSettingsNoStateChange() async {
        let store = TestStore(initialState: CalendarPickerFeature.State()) {
            CalendarPickerFeature()
        } withDependencies: {
            $0.calendarAsync.openCalendarSettings = {}
        }

        await store.send(.tapOpenSettings)
    }

    @Test("selectCalendar updates shared state")
    func selectCalendarUpdatesState() async {
        let store = TestStore(initialState: CalendarPickerFeature.State()) {
            CalendarPickerFeature()
        }

        await store.send(.selectCalendar(CalendarId("test-cal-id"))) {
            $0.$selectedCalendar.withLock { $0 = CalendarId("test-cal-id") }
        }
    }

    @Test("selectCalendar with a loaded list syncs title and source")
    func selectCalendarWritesDescriptor() async {
        let calendar = EKCalendar(for: .event, eventStore: EKEventStore())
        calendar.title = "Family"

        let store = TestStore(initialState: {
            var state = CalendarPickerFeature.State()
            state.availableCalendars = [calendar]
            return state
        }()) {
            CalendarPickerFeature()
        }

        // An unsaved EKCalendar has no source, so the descriptor's source
        // half is empty here; live picks carry the real source title.
        await store.send(.selectCalendar(CalendarId(calendar.calendarIdentifier))) {
            $0.$selectedCalendar.withLock { $0 = CalendarId(calendar.calendarIdentifier) }
            $0.$calendarDescriptor.withLock {
                $0 = CalendarDescriptor(title: "Family", sourceTitle: "")
            }
        }
    }

    @Test("selectCalendar(nil) syncs a deliberate None")
    func selectCalendarNilSyncsNoSelection() async {
        let store = TestStore(initialState: CalendarPickerFeature.State()) {
            CalendarPickerFeature()
        }
        store.state.$selectedCalendar.withLock { $0 = CalendarId("was-picked") }
        store.state.$calendarDescriptor.withLock {
            $0 = CalendarDescriptor(title: "Family", sourceTitle: "iCloud")
        }

        await store.send(.selectCalendar(nil)) {
            $0.$selectedCalendar.withLock { $0 = nil }
            $0.$calendarDescriptor.withLock { $0 = .noSelection }
        }
    }

    @Test("needsRePick flags an unresolved descriptor but never a synced None")
    func needsRePick() async {
        let state = CalendarPickerFeature.State()
        #expect(!state.needsRePick)
        state.$calendarDescriptor.withLock {
            $0 = CalendarDescriptor(title: "Family", sourceTitle: "iCloud")
        }
        #expect(state.needsRePick)
        state.$calendarDescriptor.withLock { $0 = .noSelection }
        #expect(!state.needsRePick)
    }

    @Test("restricted status shows restricted state")
    func restrictedStatus() async {
        let store = TestStore(initialState: CalendarPickerFeature.State()) {
            CalendarPickerFeature()
        } withDependencies: {
            $0.calendarAsync.calendarAccess = { .restricted }
        }

        await store.send(.onAppear) {
            $0.calendarStatus = .restricted
        }
    }
}
