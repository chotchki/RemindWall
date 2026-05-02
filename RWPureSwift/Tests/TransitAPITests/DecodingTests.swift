import Foundation
import Testing

@testable import TransitAPI

@Suite("OBA decoder tests")
struct DecodingTests {

    private func loadFixture(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            Issue.record("Missing fixture: \(name).json")
            return Data()
        }
        return try Data(contentsOf: url)
    }

    @Test("arrivals.json decodes to three predictions with correct stopId")
    func decodeArrivals() throws {
        let data = try loadFixture("arrivals")
        let envelope = try OBAEnvelope<OBAArrivalsEntry>.decode(from: data)
        let preds = envelope.data.entry?.toPredictions() ?? []

        #expect(preds.count == 3)
        #expect(preds.allSatisfy { $0.stopId == "1_75403" })
    }

    @Test("predictedArrivalTime == 0 maps to nil predictedArrival and isLive == false")
    func zeroPredictedTimeIsNil() throws {
        let data = try loadFixture("arrivals")
        let envelope = try OBAEnvelope<OBAArrivalsEntry>.decode(from: data)
        let preds = envelope.data.entry?.toPredictions() ?? []

        let scheduledOnly = preds.first { $0.tripId == "1_45872999" }
        #expect(scheduledOnly != nil)
        #expect(scheduledOnly?.predictedArrival == nil)
        #expect(scheduledOnly?.scheduledArrival != nil)
        #expect(scheduledOnly?.isLive == false)
        // effectiveArrival falls back to scheduledArrival
        #expect(scheduledOnly?.effectiveArrival == scheduledOnly?.scheduledArrival)
    }

    @Test("predicted == true with non-zero time gives isLive == true")
    func livePrediction() throws {
        let data = try loadFixture("arrivals")
        let envelope = try OBAEnvelope<OBAArrivalsEntry>.decode(from: data)
        let preds = envelope.data.entry?.toPredictions() ?? []

        let live = preds.first { $0.tripId == "1_45872551" }
        #expect(live != nil)
        #expect(live?.isLive == true)
        #expect(live?.predictedArrival != nil)
        #expect(live?.scheduledArrival != nil)
    }

    @Test("lateness is positive when predicted > scheduled")
    func latenessPositive() throws {
        let data = try loadFixture("arrivals")
        let envelope = try OBAEnvelope<OBAArrivalsEntry>.decode(from: data)
        let preds = envelope.data.entry?.toPredictions() ?? []

        // First trip: scheduled 1746118900000, predicted 1746118960000 → 60s late
        let first = preds.first { $0.tripId == "1_45872551" }
        #expect(first?.lateness == 60.0)

        // Third trip: scheduled 1746120100000, predicted 1746120400000 → 300s late
        let third = preds.first { $0.tripId == "1_45873222" }
        #expect(third?.lateness == 300.0)
    }

    @Test("lateness is nil when only scheduled time is available")
    func latenessNilWhenScheduleOnly() throws {
        let data = try loadFixture("arrivals")
        let envelope = try OBAEnvelope<OBAArrivalsEntry>.decode(from: data)
        let preds = envelope.data.entry?.toPredictions() ?? []
        let scheduledOnly = preds.first { $0.tripId == "1_45872999" }
        #expect(scheduledOnly?.lateness == nil)
    }

    @Test("client-side route filter selects only requested routeId")
    func clientSideRouteFilter() throws {
        let data = try loadFixture("arrivals")
        let envelope = try OBAEnvelope<OBAArrivalsEntry>.decode(from: data)
        let preds = envelope.data.entry?.toPredictions() ?? []

        let route12 = preds.filter { $0.routeId == "1_100224" }
        let route40 = preds.filter { $0.routeId == "1_100479" }
        #expect(route12.count == 2)
        #expect(route40.count == 1)
    }

    @Test("stop.json decodes to StopInfo with routeIds")
    func decodeStop() throws {
        let data = try loadFixture("stop")
        let envelope = try OBAEnvelope<OBAStop>.decode(from: data)
        let stop = envelope.data.entry?.toModel()

        #expect(stop?.stopId == "1_75403")
        #expect(stop?.code == "75403")
        #expect(stop?.name == "3rd Ave & Pike St")
        #expect(stop?.routeIds == ["1_100224", "1_100479"])
    }

    @Test("route.json decodes to RouteInfo with shortName + agencyId")
    func decodeRoute() throws {
        let data = try loadFixture("route")
        let envelope = try OBAEnvelope<OBARoute>.decode(from: data)
        let route = envelope.data.entry?.toModel()

        #expect(route?.routeId == "1_100224")
        #expect(route?.shortName == "12")
        #expect(route?.longName == "Capitol Hill - Downtown")
        #expect(route?.agencyId == "1")
    }

    @Test("unauthorized envelope throws TransitAPIError.unauthorized")
    func unauthorizedEnvelope() throws {
        let data = try loadFixture("unauthorized")
        #expect(throws: TransitAPIError.unauthorized) {
            _ = try OBAEnvelope<OBAEmptyEntry>.decode(from: data)
        }
    }

    @Test("rate gate spaces requests at least 110ms apart")
    func rateGateSpacing() async {
        let gate = OBARateGate()
        let start = Date()
        await gate.acquire()
        await gate.acquire()
        await gate.acquire()
        let elapsed = Date().timeIntervalSince(start)
        // Two waits of ≥110ms each (the first call passes through immediately).
        #expect(elapsed >= 0.220, "expected ≥220ms total, got \(elapsed)")
    }
}
