import Dependencies
#if canImport(AppKit)
import AppKit
#endif
import DependenciesMacros

@DependencyClient
public struct CursorClient: Sendable {
    /// Hides the cursor.
    public var hide: @Sendable () -> Void

    /// Unhides the cursor.
    public var unhide: @Sendable () -> Void
}

extension CursorClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            hide: {
                #if !DEBUG && targetEnvironment(macCatalyst)
                NSCursor.hide()
                #endif
            },
            unhide: {
                #if !DEBUG && targetEnvironment(macCatalyst)
                NSCursor.unhide()
                #endif
            }
        )
    }
}

extension CursorClient: TestDependencyKey {
    public static let testValue = Self()

    public static var previewValue: Self {
        Self(
            hide: {},
            unhide: {}
        )
    }
}

extension DependencyValues {
    public var cursorClient: CursorClient {
        get { self[CursorClient.self] }
        set { self[CursorClient.self] = newValue }
    }
}
