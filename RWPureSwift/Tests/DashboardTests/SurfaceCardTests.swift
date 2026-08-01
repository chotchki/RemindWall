import Dao
import DependenciesTestSupport
import Foundation
import Testing

@testable import Dashboard

/// D1.4: the migrated surfaces express themselves as rail cards.
@MainActor
@Suite("Surface Card Mapping Tests", .dependencies {
    // Feature States hold .syncedSetting keys, which read the database at init.
    $0.defaultDatabase = try! $0.appDatabase()
    $0.uuid = .incrementing
})
struct SurfaceCardTests {
    private func arrival(
        _ label: String,
        isLate: Bool,
        etaSeconds: TimeInterval,
        isLive: Bool = true
    ) -> DisplayArrival {
        DisplayArrival(
            id: MonitoredStop.ID(UUID()),
            label: label,
            routeShortName: "12",
            etaText: "4 min",
            etaSeconds: etaSeconds,
            isLate: isLate,
            isLive: isLive
        )
    }

    @Test("A late arrival maps to the lateBus priority class")
    func lateArrivalPriority() {
        var state = BusArrivalsFeature.State()
        state.arrivals = [
            arrival("School bus", isLate: true, etaSeconds: 240),
            arrival("Commute", isLate: false, etaSeconds: 840),
        ]

        let cards = state.railCards
        #expect(cards.count == 2)
        #expect(cards[0].priority == .lateBus)
        #expect(cards[0].etaSeconds == 240)
        #expect(cards[1].priority == .onTimeBus)
        guard case let .transit(route, label, etaText, isLate, isLive) = cards[0].content else {
            Issue.record("expected transit content")
            return
        }
        #expect(route == "12")
        #expect(label == "School bus")
        #expect(etaText == "4 min")
        #expect(isLate)
        #expect(isLive)
    }

    @Test("A fetch failure with nothing to show collapses to one error chip")
    func errorChipWhenEmpty() {
        var state = BusArrivalsFeature.State()
        state.arrivals = []
        state.lastError = "unauthorized"

        let cards = state.railCards
        #expect(cards.count == 1)
        #expect(cards[0].priority == .errorChip)
        #expect(cards[0].content == .errorChip(message: "Cannot reach transit API: unauthorized"))
    }

    @Test("An error with arrivals still showing adds no chip - stale beats noise")
    func noErrorChipWithArrivals() {
        var state = BusArrivalsFeature.State()
        state.arrivals = [arrival("School bus", isLate: false, etaSeconds: 240)]
        state.lastError = "timeout"

        #expect(state.railCards.count == 1)
        #expect(state.railCards[0].priority == .onTimeBus)
    }

    @Test("No next event means no up-next card")
    func noUpNextCard() {
        let state = CalendarEventsFeature.State()
        #expect(state.railCards.isEmpty)
    }

    @Test("The next event maps to an upNext card with the ETA tiebreaker")
    func upNextCard() {
        var state = CalendarEventsFeature.State()
        state.nextEventTitle = "Dentist"
        state.nextEventTimeUntil = "25min"
        state.nextEventLeadingEmoji = "🦷"
        state.nextEventStartsInSeconds = 1500

        let cards = state.railCards
        #expect(cards.count == 1)
        #expect(cards[0].priority == .upNext)
        #expect(cards[0].etaSeconds == 1500)
        #expect(cards[0].content == .upNext(title: "Dentist", timeUntil: "in 25min", emoji: "🦷"))
    }

    @Test("The dashboard rail orders bus and calendar cards across features")
    func dashboardAssemblesAcrossFeatures() {
        var state = DashboardFeature.State()
        state.busArrivalsState.arrivals = [
            arrival("Commute", isLate: false, etaSeconds: 840),
            arrival("School bus", isLate: true, etaSeconds: 240),
        ]
        state.calendarEventsState.nextEventTitle = "Dentist"
        state.calendarEventsState.nextEventTimeUntil = "25min"
        state.calendarEventsState.nextEventStartsInSeconds = 1500

        let rail = state.rail
        #expect(rail.visible.map(\.priority) == [.lateBus, .onTimeBus, .upNext])
        #expect(rail.overflowCount == 0)
    }
}
