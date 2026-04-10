import Dependencies
import DependenciesMacros
import Foundation
#if targetEnvironment(macCatalyst)
import IOKit
import UIKit
#elseif canImport(UIKit)
import UIKit
#endif

@DependencyClient
public struct ScreenControl: Sendable {
    /// Gets the current screen brightness (0.0 to 1.0).
    public var getBrightness: @Sendable () async -> CGFloat = { 1.0 }

    /// Sets the screen brightness (0.0 to 1.0).
    public var setBrightness: @Sendable (CGFloat) async -> Void
}

extension ScreenControl: DependencyKey {
    public static var liveValue: Self {
        Self(
            getBrightness: {
                #if targetEnvironment(macCatalyst)
                return DDCBrightness.getBrightness() ?? 1.0
                #elseif canImport(UIKit)
                return await MainActor.run {
                    guard let scene = UIApplication.shared.connectedScenes.first,
                          let windowSceneDelegate = scene.delegate as? UIWindowSceneDelegate,
                          let window = windowSceneDelegate.window else {
                            return 1.0
                    }

                    return window?.windowScene?.screen.brightness ?? 1.0
                }
                #else
                return 1.0
                #endif
            },
            setBrightness: { brightness in
                #if targetEnvironment(macCatalyst)
                DDCBrightness.setBrightness(brightness)
                #elseif canImport(UIKit)
                await MainActor.run {
                    guard let scene = UIApplication.shared.connectedScenes.first,
                          let windowSceneDelegate = scene.delegate as? UIWindowSceneDelegate,
                          let window = windowSceneDelegate.window,
                          let screen = window?.windowScene?.keyWindow?.screen else {
                            return
                    }

                    screen.brightness = 1.0
                }
                #endif
            }
        )
    }
}

extension ScreenControl: TestDependencyKey {
    public static let testValue = Self()

    public static var previewValue: Self {
        Self(
            getBrightness: { 0.75 },
            setBrightness: { _ in }
        )
    }
}

extension DependencyValues {
    public var screenControl: ScreenControl {
        get { self[ScreenControl.self] }
        set { self[ScreenControl.self] = newValue }
    }
}

// MARK: - DDC/CI Brightness Control (Mac Catalyst)

#if targetEnvironment(macCatalyst)

// Private IOKit functions for DDC over I2C on Apple Silicon.
// These are not in public headers but are stable symbols in IOKit.framework.
// Reference: MonitorControl (https://github.com/MonitorControl/MonitorControl)

@_silgen_name("IOAVServiceCreateWithService")
private func IOAVServiceCreateWithService(
    _ allocator: CFAllocator,
    _ service: io_service_t
) -> CFTypeRef?

@_silgen_name("IOAVServiceWriteI2C")
private func IOAVServiceWriteI2C(
    _ service: CFTypeRef,
    _ chipAddress: UInt32,
    _ dataAddress: UInt32,
    _ inputBuffer: UnsafeMutablePointer<UInt8>,
    _ inputBufferSize: UInt32
) -> IOReturn

@_silgen_name("IOAVServiceReadI2C")
private func IOAVServiceReadI2C(
    _ service: CFTypeRef,
    _ chipAddress: UInt32,
    _ dataAddress: UInt32,
    _ outputBuffer: UnsafeMutablePointer<UInt8>,
    _ outputBufferSize: UInt32
) -> IOReturn

enum DDCBrightness {
    private static let chipAddress: UInt32 = 0x37
    private static let dataAddress: UInt32 = 0x51
    private static let brightnessVCP: UInt8 = 0x10

    /// Finds the first external display's IOAVService.
    private static func findDisplayService() -> CFTypeRef? {
        // Check that at least one external display is connected before probing IOKit.
        // IOAVServiceCreateWithService crashes when called without an external display.
        let hasExternalScreen = DispatchQueue.main.sync {
            UIApplication.shared.openSessions.contains { session in
                session.scene?.session.role == .windowExternalDisplayNonInteractive
            }
        }
        guard hasExternalScreen else {
            return nil
        }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("DCPAVServiceProxy"),
            &iterator
        ) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var ioService = IOIteratorNext(iterator)
        while ioService != IO_OBJECT_NULL {
            defer { IOObjectRelease(ioService) }

            if let avService = IOAVServiceCreateWithService(kCFAllocatorDefault, ioService) {
                return avService
            }

            ioService = IOIteratorNext(iterator)
        }
        return nil
    }

    /// Sends a DDC/CI Set VCP Feature command.
    private static func setVCPFeature(service: CFTypeRef, vcp: UInt8, value: UInt16) -> Bool {
        var data: [UInt8] = [
            0x84,                      // 0x80 | (payload_length + 1)
            0x03,                      // Set VCP Feature opcode
            vcp,
            UInt8(value >> 8),         // Value high byte
            UInt8(value & 0xFF),       // Value low byte
            0                          // Checksum placeholder
        ]

        var checksum: UInt8 = 0x6E ^ UInt8(dataAddress & 0xFF)
        for i in 0..<(data.count - 1) {
            checksum ^= data[i]
        }
        data[data.count - 1] = checksum

        return data.withUnsafeMutableBufferPointer { buffer in
            IOAVServiceWriteI2C(
                service, chipAddress, dataAddress,
                buffer.baseAddress!, UInt32(buffer.count)
            ) == KERN_SUCCESS
        }
    }

    /// Sends a DDC/CI Get VCP Feature request and reads the response.
    private static func getVCPFeature(service: CFTypeRef, vcp: UInt8) -> (current: UInt16, max: UInt16)? {
        var request: [UInt8] = [
            0x82,                      // 0x80 | (payload_length + 1)
            0x01,                      // Get VCP Feature opcode
            vcp,
            0                          // Checksum placeholder
        ]

        var checksum: UInt8 = 0x6E ^ UInt8(dataAddress & 0xFF)
        for i in 0..<(request.count - 1) {
            checksum ^= request[i]
        }
        request[request.count - 1] = checksum

        let writeOK = request.withUnsafeMutableBufferPointer { buffer in
            IOAVServiceWriteI2C(
                service, chipAddress, dataAddress,
                buffer.baseAddress!, UInt32(buffer.count)
            ) == KERN_SUCCESS
        }
        guard writeOK else { return nil }

        // Wait for the display to process the request
        Thread.sleep(forTimeInterval: 0.04)

        // Read response (11 bytes for Get VCP Feature Reply)
        var reply = [UInt8](repeating: 0, count: 11)
        let readOK = reply.withUnsafeMutableBufferPointer { buffer in
            IOAVServiceReadI2C(
                service, chipAddress, dataAddress,
                buffer.baseAddress!, UInt32(buffer.count)
            ) == KERN_SUCCESS
        }
        guard readOK else { return nil }

        // Validate checksum
        var replyChecksum: UInt8 = 0x50
        for i in 0..<(reply.count - 1) {
            replyChecksum ^= reply[i]
        }
        guard replyChecksum == reply[reply.count - 1] else { return nil }

        let maxValue = (UInt16(reply[6]) << 8) | UInt16(reply[7])
        let currentValue = (UInt16(reply[8]) << 8) | UInt16(reply[9])
        return (current: currentValue, max: maxValue)
    }

    /// Gets the current monitor brightness as a value from 0.0 to 1.0.
    static func getBrightness() -> CGFloat? {
        guard let service = findDisplayService() else { return nil }
        guard let result = getVCPFeature(service: service, vcp: brightnessVCP) else { return nil }
        guard result.max > 0 else { return nil }
        return CGFloat(result.current) / CGFloat(result.max)
    }

    /// Sets the monitor brightness from a value of 0.0 to 1.0.
    @discardableResult
    static func setBrightness(_ value: CGFloat) -> Bool {
        guard let service = findDisplayService() else { return false }

        // Read the max value from the display, fall back to DDC standard 100
        let maxValue: UInt16
        if let result = getVCPFeature(service: service, vcp: brightnessVCP) {
            maxValue = result.max
        } else {
            maxValue = 100
        }

        let clamped = max(0, min(1, value))
        let ddcValue = UInt16(clamped * CGFloat(maxValue))
        return setVCPFeature(service: service, vcp: brightnessVCP, value: ddcValue)
    }
}

#endif
