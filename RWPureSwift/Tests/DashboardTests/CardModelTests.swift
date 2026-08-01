import Foundation
import Testing

@testable import Dashboard

@Suite("Card Model Tests")
struct CardModelTests {
    private func card(
        _ id: String,
        _ priority: RailPriority,
        eta: TimeInterval? = nil
    ) -> RailCard {
        RailCard(
            id: id,
            priority: priority,
            etaSeconds: eta,
            content: .errorChip(message: id)
        )
    }

    @Test("Priority classes order late/degraded first, chrome last")
    func priorityClassOrdering() {
        let shuffled = [
            card("error", .errorChip),
            card("ontime-route", .onTimeRoute, eta: 600),
            card("upnext", .upNext, eta: 1500),
            card("late-bus", .lateBus, eta: 240),
            card("ontime-bus", .onTimeBus, eta: 840),
            card("slow-route", .slowRoute, eta: 1080),
        ]
        let rail = DashboardRail.assemble(shuffled, capacity: 10)
        #expect(rail.visible.map(\.id) == [
            "late-bus", "slow-route", "ontime-bus", "ontime-route", "upnext", "error",
        ])
        #expect(rail.overflowCount == 0)
    }

    @Test("Within a class the soonest ETA wins")
    func etaTiebreaker() {
        let rail = DashboardRail.assemble([
            card("bus-later", .onTimeBus, eta: 840),
            card("bus-sooner", .onTimeBus, eta: 240),
        ])
        #expect(rail.visible.map(\.id) == ["bus-sooner", "bus-later"])
    }

    @Test("A nil ETA sorts after every numbered ETA in its class")
    func nilEtaSortsLast() {
        let rail = DashboardRail.assemble([
            card("bus-no-eta", .onTimeBus),
            card("bus-timed", .onTimeBus, eta: 3600),
        ])
        #expect(rail.visible.map(\.id) == ["bus-timed", "bus-no-eta"])
    }

    @Test("Full ties fall back to id so refreshes never reshuffle")
    func deterministicTies() {
        let cards = [
            card("b", .onTimeBus, eta: 300),
            card("a", .onTimeBus, eta: 300),
            card("c", .onTimeBus, eta: 300),
        ]
        let first = DashboardRail.assemble(cards)
        let second = DashboardRail.assemble(cards.reversed())
        #expect(first.visible.map(\.id) == ["a", "b", "c"])
        #expect(first == second)
    }

    @Test("Capacity caps the stack and reports the cut count")
    func capacityAndOverflow() {
        let cards = (0..<6).map { card("bus-\($0)", .onTimeBus, eta: TimeInterval($0 * 60)) }
        let rail = DashboardRail.assemble(cards, capacity: DashboardRail.wallCapacity)
        #expect(rail.visible.count == 4)
        #expect(rail.overflowCount == 2)
        // The cut cards are the LOWEST priority ones, never the urgent ones.
        #expect(rail.visible.map(\.id) == ["bus-0", "bus-1", "bus-2", "bus-3"])
    }

    @Test("Under capacity nothing is cut")
    func underCapacity() {
        let rail = DashboardRail.assemble(
            [card("only", .lateBus, eta: 60)],
            capacity: DashboardRail.padCapacity
        )
        #expect(rail.visible.count == 1)
        #expect(rail.overflowCount == 0)
    }

    @Test("Empty input assembles the empty rail")
    func emptyInput() {
        #expect(DashboardRail.assemble([]) == .empty)
    }
}
