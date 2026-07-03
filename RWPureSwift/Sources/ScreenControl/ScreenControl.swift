import Dependencies
import DependenciesMacros
import Foundation
import os
#if canImport(UIKit)
import UIKit
#endif

/// Errors from the brightness/display-power pipeline. Failures are THROWN, not
/// masked — the old `?? 1.0` fallback made a failed DDC read indistinguishable
/// from a bright screen and broke the restore logic.
public enum ScreenControlError: Error, Equatable {
    /// ddcd didn't answer (not running, wrong port).
    case daemonUnreachable(String)
    /// ddcd answered with an error (m1ddc failure, timeout, no display).
    case daemonError(status: Int, message: String)
    case invalidResponse
}

@DependencyClient
public struct ScreenControl: Sendable {
    /// Current screen brightness (0.0 to 1.0). Throws when it can't be read —
    /// callers must not fabricate a value.
    public var getBrightness: @Sendable () async throws -> CGFloat

    /// Sets the screen brightness (0.0 to 1.0).
    public var setBrightness: @Sendable (CGFloat) async throws -> Void

    /// True display power (Mac kiosk: panel standby via ddcd /display).
    /// No-op on iOS — the brightness path is the iOS dim mechanism.
    public var setDisplayPower: @Sendable (_ on: Bool) async throws -> Void

    /// Whether brightness control is usable right now (ddcd reachable and
    /// m1ddc present on the Mac; always true on iOS).
    public var isAvailable: @Sendable () async -> Bool = { false }
}

let logger = Logger(subsystem: "RemindWall", category: "ScreenControl")

extension ScreenControl: DependencyKey {
    public static var liveValue: Self {
        #if targetEnvironment(macCatalyst)
        let client = DdcdClient.live()
        return Self(
            getBrightness: { try await client.getBrightness() },
            setBrightness: { try await client.setBrightness($0) },
            setDisplayPower: { try await client.setDisplayPower(on: $0) },
            isAvailable: { await client.healthy() }
        )
        #elseif canImport(UIKit)
        return Self(
            getBrightness: {
                await MainActor.run {
                    guard let scene = UIApplication.shared.connectedScenes.first,
                          let windowSceneDelegate = scene.delegate as? UIWindowSceneDelegate,
                          let window = windowSceneDelegate.window else {
                            return 1.0
                    }

                    return window?.windowScene?.screen.brightness ?? 1.0
                }
            },
            setBrightness: { brightness in
                await MainActor.run {
                    guard let scene = UIApplication.shared.connectedScenes.first,
                          let windowSceneDelegate = scene.delegate as? UIWindowSceneDelegate,
                          let window = windowSceneDelegate.window,
                          let screen = window?.windowScene?.keyWindow?.screen else {
                            return
                    }

                    screen.brightness = brightness
                }
            },
            setDisplayPower: { _ in },
            isAvailable: { true }
        )
        #else
        return Self(
            getBrightness: { 1.0 },
            setBrightness: { _ in },
            setDisplayPower: { _ in },
            isAvailable: { false }
        )
        #endif
    }
}

extension ScreenControl: TestDependencyKey {
    public static let testValue = Self()

    public static var previewValue: Self {
        Self(
            getBrightness: { 0.75 },
            setBrightness: { _ in },
            setDisplayPower: { _ in },
            isAvailable: { true }
        )
    }
}

extension DependencyValues {
    public var screenControl: ScreenControl {
        get { self[ScreenControl.self] }
        set { self[ScreenControl.self] = newValue }
    }
}

// MARK: - ddcd HTTP client (Mac Catalyst)

/// Talks to the local ddcd daemon. The daemon owns the hard problems
/// (m1ddc timeouts, DDC bus serialization, max-luminance caching); this is a
/// thin, honest transport. Internal for tests — production reaches it only
/// through ScreenControl.liveValue.
struct DdcdClient: Sendable {
    let baseURL: URL
    let session: URLSession

    /// Every request carries this header; ddcd refuses bare requests (the
    /// kiosk box serves public traffic, localhost is not a trust boundary).
    static let guardHeader = "x-ddcd"

    static func live() -> DdcdClient {
        let port = ProcessInfo.processInfo.environment["DDCD_PORT"].flatMap(Int.init) ?? 8377
        let config = URLSessionConfiguration.ephemeral
        // Above ddcd's worst case (5s m1ddc timeout + retry backoff), below
        // the 30s monitor tick so calls can't stack.
        config.timeoutIntervalForRequest = 10
        return DdcdClient(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            session: URLSession(configuration: config)
        )
    }

    private struct BrightnessResponse: Decodable {
        let brightness: Double
    }

    private struct HealthResponse: Decodable {
        let status: String
        let m1ddc_present: Bool
    }

    private struct ErrorResponse: Decodable {
        let error: String
    }

    private struct SetBrightnessBody: Encodable {
        let brightness: Double
    }

    private struct DisplayPowerBody: Encodable {
        let on: Bool
    }

    func getBrightness() async throws -> CGFloat {
        let data = try await send("GET", "brightness")
        guard let response = try? JSONDecoder().decode(BrightnessResponse.self, from: data) else {
            throw ScreenControlError.invalidResponse
        }
        return CGFloat(response.brightness)
    }

    func setBrightness(_ value: CGFloat) async throws {
        _ = try await send("PUT", "brightness", body: SetBrightnessBody(brightness: Double(value)))
    }

    func setDisplayPower(on: Bool) async throws {
        _ = try await send("PUT", "display", body: DisplayPowerBody(on: on))
    }

    /// Available means the daemon answers AND it can see m1ddc — a running
    /// daemon with no binary would fail every operation.
    func healthy() async -> Bool {
        guard let data = try? await send("GET", "health"),
              let health = try? JSONDecoder().decode(HealthResponse.self, from: data) else {
            return false
        }
        return health.status == "ok" && health.m1ddc_present
    }

    private func send(_ method: String, _ path: String, body: (some Encodable)? = nil as Int?) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("1", forHTTPHeaderField: Self.guardHeader)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger.warning("ddcd unreachable: \(error.localizedDescription, privacy: .public)")
            throw ScreenControlError.daemonUnreachable(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ScreenControlError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
                ?? String(data: data, encoding: .utf8) ?? "no detail"
            logger.warning("ddcd \(method, privacy: .public) /\(path, privacy: .public) -> \(http.statusCode): \(message, privacy: .public)")
            throw ScreenControlError.daemonError(status: http.statusCode, message: message)
        }
        return data
    }
}
