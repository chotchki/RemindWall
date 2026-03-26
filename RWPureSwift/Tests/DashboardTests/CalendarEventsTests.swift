import AppTypes
import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Testing

@testable import Dashboard

@MainActor
@Suite("CalendarEvents Feature Tests")
struct CalendarEventsTests {

    @Test("startMonitoring fires immediate tick then loops")
    func startMonitoring() async {
        let clock = TestClock()

        let store = TestStore(initialState: CalendarEventsFeature.State()) {
            CalendarEventsFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(Date())
        }

        store.exhaustivity = .off

        await store.send(.startMonitoring)

        // Immediate tick with no calendar selected returns nil events
        await store.receive(\.tick)
        await store.receive(\._eventsLoaded)

        await store.finish()
    }

    @Test("tick without selected calendar clears events")
    func tickNoCalendar() async {
        let store = TestStore(initialState: CalendarEventsFeature.State()) {
            CalendarEventsFeature()
        } withDependencies: {
            $0.date = .constant(Date())
        }

        await store.send(.tick)
        await store.receive(._eventsLoaded(
            currentTitle: nil,
            nextTitle: nil,
            nextTimeUntil: nil,
            nextLeadingEmoji: nil
        ))
    }

    @Test("tick with selected calendar calls calendarAsync")
    func tickWithCalendar() async {
        var state = CalendarEventsFeature.State()
        state.$selectedCalendar.withLock { $0 = CalendarId("test-cal") }

        let store = TestStore(initialState: state) {
            CalendarEventsFeature()
        } withDependencies: {
            $0.date = .constant(Date())
            $0.calendarAsync.getActiveEvent = { _, _ in nil }
            $0.calendarAsync.getNextEvent = { _, _ in nil }
        }

        store.exhaustivity = .off

        await store.send(.tick)

        await store.receive(\._eventsLoaded) {
            $0.currentEventTitle = nil
            $0.nextEventTitle = nil
            $0.nextEventTimeUntil = nil
            $0.nextEventLeadingEmoji = nil
        }
    }

    @Test("_eventsLoaded updates all state fields")
    func eventsLoadedUpdatesState() async {
        let store = TestStore(initialState: CalendarEventsFeature.State()) {
            CalendarEventsFeature()
        }

        await store.send(._eventsLoaded(
            currentTitle: "Current Meeting",
            nextTitle: "Lunch",
            nextTimeUntil: "30min",
            nextLeadingEmoji: "🍕"
        )) {
            $0.currentEventTitle = "Current Meeting"
            $0.nextEventTitle = "Lunch"
            $0.nextEventTimeUntil = "30min"
            $0.nextEventLeadingEmoji = "🍕"
        }
    }

    @Test("_eventsLoaded clears state when nil")
    func eventsLoadedClearsState() async {
        var state = CalendarEventsFeature.State()
        state.currentEventTitle = "Old Meeting"
        state.nextEventTitle = "Old Next"
        state.nextEventTimeUntil = "5min"
        state.nextEventLeadingEmoji = "📅"

        let store = TestStore(initialState: state) {
            CalendarEventsFeature()
        }

        await store.send(._eventsLoaded(
            currentTitle: nil,
            nextTitle: nil,
            nextTimeUntil: nil,
            nextLeadingEmoji: nil
        )) {
            $0.currentEventTitle = nil
            $0.nextEventTitle = nil
            $0.nextEventTimeUntil = nil
            $0.nextEventLeadingEmoji = nil
        }
    }
}
