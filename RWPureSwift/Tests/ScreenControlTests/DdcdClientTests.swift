import Foundation
import Testing

@testable import ScreenControl

/// Intercepts DdcdClient's URLSession traffic. One static handler at a time —
/// the suite is serialized.
final class StubProtocol: URLProtocol {
    struct Recorded: Sendable {
        let method: String
        let path: String
        let guardHeader: String?
        let body: Data?
    }

    nonisolated(unsafe) static var handler: (@Sendable (Recorded) throws -> (status: Int, body: Data))?
    nonisolated(unsafe) static var recordings: [Recorded] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        // URLSession moves httpBody into a stream before URLProtocol sees it.
        var bodyData: Data?
        if let body = request.httpBody {
            bodyData = body
        } else if let stream = request.httpBodyStream {
            var data = Data()
            stream.open()
            defer { stream.close() }
            let bufferSize = 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            bodyData = data
        }

        let recorded = Recorded(
            method: request.httpMethod ?? "?",
            path: request.url?.path ?? "?",
            guardHeader: request.value(forHTTPHeaderField: DdcdClient.guardHeader),
            body: bodyData
        )
        Self.recordings.append(recorded)

        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (status, body) = try handler(recorded)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

@Suite("DdcdClient", .serialized)
struct DdcdClientTests {
    private func makeClient() -> DdcdClient {
        StubProtocol.handler = nil
        StubProtocol.recordings = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return DdcdClient(
            baseURL: URL(string: "http://127.0.0.1:9999")!,
            session: URLSession(configuration: config)
        )
    }

    @Test("getBrightness parses the daemon response and sends the guard header")
    func getBrightness() async throws {
        let client = makeClient()
        StubProtocol.handler = { _ in
            (200, Data(#"{"brightness":0.43,"raw":43,"max":100}"#.utf8))
        }

        let value = try await client.getBrightness()
        #expect(abs(value - 0.43) < 1e-9)

        let recorded = try #require(StubProtocol.recordings.first)
        #expect(recorded.method == "GET")
        #expect(recorded.path == "/brightness")
        #expect(recorded.guardHeader == "1")
    }

    @Test("daemon errors surface with status and message, never a fabricated value")
    func daemonErrorSurfaces() async {
        let client = makeClient()
        StubProtocol.handler = { _ in
            (502, Data(#"{"error":"Could not find a suitable external display."}"#.utf8))
        }

        do {
            _ = try await client.getBrightness()
            Issue.record("expected a throw")
        } catch let ScreenControlError.daemonError(status, message) {
            #expect(status == 502)
            #expect(message.contains("external display"))
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("setBrightness PUTs scaled JSON")
    func setBrightness() async throws {
        let client = makeClient()
        StubProtocol.handler = { _ in (204, Data()) }

        try await client.setBrightness(0.5)

        let recorded = try #require(StubProtocol.recordings.first)
        #expect(recorded.method == "PUT")
        #expect(recorded.path == "/brightness")
        let body = try #require(recorded.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Double])
        #expect(json["brightness"] == 0.5)
    }

    @Test("setDisplayPower PUTs the on flag to /display")
    func setDisplayPower() async throws {
        let client = makeClient()
        StubProtocol.handler = { _ in (204, Data()) }

        try await client.setDisplayPower(on: false)

        let recorded = try #require(StubProtocol.recordings.first)
        #expect(recorded.method == "PUT")
        #expect(recorded.path == "/display")
        let body = try #require(recorded.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Bool])
        #expect(json["on"] == false)
    }

    @Test("healthy requires ok status AND a present binary")
    func healthy() async {
        let client = makeClient()

        StubProtocol.handler = { _ in
            (200, Data(#"{"status":"ok","m1ddc_present":true}"#.utf8))
        }
        #expect(await client.healthy() == true)

        StubProtocol.handler = { _ in
            (200, Data(#"{"status":"ok","m1ddc_present":false}"#.utf8))
        }
        #expect(await client.healthy() == false)

        StubProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        #expect(await client.healthy() == false)
    }

    @Test("unreachable daemon throws daemonUnreachable")
    func unreachable() async {
        let client = makeClient()
        StubProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }

        do {
            _ = try await client.getBrightness()
            Issue.record("expected a throw")
        } catch ScreenControlError.daemonUnreachable {
            // expected
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }
}
