import AppTypes
import CalendarAsync
import ComposableArchitecture
import DependenciesTestSupport
@preconcurrency import EventKit
import Testing

@testable import EditSettingsNew_TopLevel

@MainActor
@Suite("CalendarPicker Feature Tests")
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

    @Test("binding action does not cause side effects")
    func bindingNoSideEffects() async {
        let store = TestStore(initialState: CalendarPickerFeature.State()) {
            CalendarPickerFeature()
        }

        await store.send(.binding(.set(\.calendarStatus, .fullAccess))) {
            $0.calendarStatus = .fullAccess
        }
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
