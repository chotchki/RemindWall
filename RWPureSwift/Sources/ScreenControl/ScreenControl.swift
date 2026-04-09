import Dependencies
import DependenciesMacros
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

extension ScreenControl: DependencyKey {
    public static var liveValue: Self {
        Self(
            getBrightness: {
                #if canImport(UIKit)
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
                #if canImport(UIKit)
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
