import Dependencies
import DependenciesMacros
#if canImport(IOKit)
import IOKit
#endif
#if canImport(UIKit)
import UIKit
#endif

@DependencyClient
public struct ScreenControl: Sendable {
    /// Gets the current screen brightness (0.0 to 1.0).
    public var getBrightness: @Sendable () async -> CGFloat = { 1.0 }

    /// Sets the screen brightness (0.0 to 1.0).
    public var setBrightness: @Sendable (CGFloat) async -> Void
}

// MARK: - IOKit Display Brightness (macCatalyst)

#if canImport(IOKit)

/// Typealias for IODisplayGetFloatParameter from IOGraphicsLib
/// Signature: kern_return_t IODisplayGetFloatParameter(io_service_t service, IOOptionBits options, CFStringRef parameterName, float *value)
private typealias IODisplayGetFloatParameterFunc = @convention(c) (io_service_t, UInt32, CFString, UnsafeMutablePointer<Float>) -> kern_return_t

/// Typealias for IODisplaySetFloatParameter from IOGraphicsLib
/// Signature: kern_return_t IODisplaySetFloatParameter(io_service_t service, IOOptionBits options, CFStringRef parameterName, float value)
private typealias IODisplaySetFloatParameterFunc = @convention(c) (io_service_t, UInt32, CFString, Float) -> kern_return_t

/// Loads IODisplayGetFloatParameter and IODisplaySetFloatParameter from IOKit via dlsym.
/// These symbols live in the IOKit framework but are not exposed in Swift headers.
private func loadIODisplayFunctions() -> (get: IODisplayGetFloatParameterFunc, set: IODisplaySetFloatParameterFunc)? {
    guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else {
        return nil
    }
    guard let getPtr = dlsym(handle, "IODisplayGetFloatParameter"),
          let setPtr = dlsym(handle, "IODisplaySetFloatParameter") else {
        return nil
    }
    let getFunc = unsafeBitCast(getPtr, to: IODisplayGetFloatParameterFunc.self)
    let setFunc = unsafeBitCast(setPtr, to: IODisplaySetFloatParameterFunc.self)
    return (getFunc, setFunc)
}

nonisolated(unsafe) private let brightnessKey = "brightness" as CFString

private func ioKitGetBrightness() -> CGFloat? {
    guard let funcs = loadIODisplayFunctions() else { return nil }
    var iterator = io_iterator_t()
    let result = IOServiceGetMatchingServices(
        kIOMainPortDefault,
        IOServiceMatching("IODisplayConnect"),
        &iterator
    )
    guard result == kIOReturnSuccess else { return nil }
    defer { IOObjectRelease(iterator) }

    let service = IOIteratorNext(iterator)
    guard service != IO_OBJECT_NULL else { return nil }
    defer { IOObjectRelease(service) }

    var brightness: Float = 0
    let kr = funcs.get(service, 0, brightnessKey, &brightness)
    guard kr == kIOReturnSuccess else { return nil }
    return CGFloat(brightness)
}

private func ioKitSetBrightness(_ value: CGFloat) {
    guard let funcs = loadIODisplayFunctions() else { return }
    var iterator = io_iterator_t()
    let result = IOServiceGetMatchingServices(
        kIOMainPortDefault,
        IOServiceMatching("IODisplayConnect"),
        &iterator
    )
    guard result == kIOReturnSuccess else { return }
    defer { IOObjectRelease(iterator) }

    let service = IOIteratorNext(iterator)
    guard service != IO_OBJECT_NULL else { return }
    defer { IOObjectRelease(service) }

    _ = funcs.set(service, 0, brightnessKey, Float(value))
}

#endif

extension ScreenControl: DependencyKey {
    public static var liveValue: Self {
        Self(
            getBrightness: {
                #if targetEnvironment(macCatalyst)
                return ioKitGetBrightness() ?? 1.0
                #elseif canImport(UIKit)
                return await MainActor.run { UIScreen.main.brightness }
                #else
                return 1.0
                #endif
            },
            setBrightness: { brightness in
                #if targetEnvironment(macCatalyst)
                ioKitSetBrightness(brightness)
                #elseif canImport(UIKit)
                await MainActor.run { UIScreen.main.brightness = brightness }
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
