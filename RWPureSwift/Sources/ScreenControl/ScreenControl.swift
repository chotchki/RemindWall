import Dependencies
import DependenciesMacros
import Foundation
#if canImport(UIKit)
import UIKit
#endif

@DependencyClient
public struct ScreenControl: Sendable {
    /// Gets the current screen brightness (0.0 to 1.0).
    public var getBrightness: @Sendable () async -> CGFloat = { 1.0 }

    /// Sets the screen brightness (0.0 to 1.0).
    public var setBrightness: @Sendable (CGFloat) async -> Void

    /// Checks whether the external display brightness tool (m1ddc) is available.
    /// Always returns true on iOS (uses built-in UIScreen).
    public var isAvailable: @Sendable () async -> Bool = { true }
}

extension ScreenControl: DependencyKey {
    public static var liveValue: Self {
        Self(
            getBrightness: {
                #if targetEnvironment(macCatalyst)
                return M1DDCBrightness.getBrightness() ?? 1.0
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
                M1DDCBrightness.setBrightness(brightness)
                #elseif canImport(UIKit)
                await MainActor.run {
                    guard let scene = UIApplication.shared.connectedScenes.first,
                          let windowSceneDelegate = scene.delegate as? UIWindowSceneDelegate,
                          let window = windowSceneDelegate.window,
                          let screen = window?.windowScene?.keyWindow?.screen else {
                            return
                    }

                    screen.brightness = brightness
                }
                #endif
            },
            isAvailable: {
                #if targetEnvironment(macCatalyst)
                return M1DDCBrightness.isAvailable()
                #else
                return true
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
            setBrightness: { _ in },
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

// MARK: - m1ddc CLI Brightness Control (Mac Catalyst)

#if targetEnvironment(macCatalyst)

enum M1DDCBrightness {
    /// Common install locations for m1ddc (Homebrew on Apple Silicon / Intel).
    private static let searchPaths = [
        "/opt/homebrew/bin/m1ddc",
        "/usr/local/bin/m1ddc",
    ]

    /// Cached path once found, to avoid repeated lookups.
    nonisolated(unsafe) private static var cachedPath: String?
    nonisolated(unsafe) private static var hasSearched = false

    /// Returns the path to the m1ddc binary, or nil if not found.
    /// Tries FileManager first, then falls back to actually invoking each
    /// candidate path (works around sandbox restrictions on file metadata).
    private static func findBinary() -> String? {
        if hasSearched { return cachedPath }

        // First try FileManager (fast, works outside sandbox)
        if let path = searchPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            cachedPath = path
            hasSearched = true
            return path
        }

        // Fallback: try to actually spawn each candidate.
        // In a sandbox, FileManager may deny stat() but posix_spawn may still work.
        for path in searchPaths {
            if canSpawn(path) {
                cachedPath = path
                hasSearched = true
                return path
            }
        }

        hasSearched = true
        return nil
    }

    /// Attempts to spawn the binary with no arguments to test reachability.
    private static func canSpawn(_ path: String) -> Bool {
        let cPath = strdup(path)
        defer { free(cPath) }
        let argv: [UnsafeMutablePointer<CChar>?] = [cPath, nil]

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        // Silence all output
        posix_spawn_file_actions_addopen(&fileActions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)

        var pid: pid_t = 0
        let result = posix_spawn(&pid, path, &fileActions, nil, argv, environ)
        if result == 0 {
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            return true
        }
        return false
    }

    /// Whether m1ddc is installed and executable.
    static func isAvailable() -> Bool {
        findBinary() != nil
    }

    /// Runs m1ddc with the given arguments using posix_spawn and returns trimmed stdout, or nil on failure.
    /// (Process/NSTask is unavailable in Mac Catalyst, so we use posix_spawn directly.)
    private static func run(_ arguments: [String]) -> String? {
        guard let path = findBinary() else { return nil }

        // Set up a pipe for stdout
        var pipeFDs: [Int32] = [0, 0]
        guard pipe(&pipeFDs) == 0 else { return nil }

        // Build argv: [path, arg1, arg2, ..., nil]
        let allArgs = [path] + arguments
        let cArgs = allArgs.map { strdup($0) } + [nil]
        defer { cArgs.forEach { $0.map { free($0) } } }

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        // Redirect stdout to write end of pipe
        posix_spawn_file_actions_adddup2(&fileActions, pipeFDs[1], STDOUT_FILENO)
        // Close both pipe ends in child (inherited via dup2 for stdout)
        posix_spawn_file_actions_addclose(&fileActions, pipeFDs[0])
        posix_spawn_file_actions_addclose(&fileActions, pipeFDs[1])
        // Send stderr to /dev/null
        posix_spawn_file_actions_addopen(&fileActions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)

        var pid: pid_t = 0
        let spawnResult = posix_spawn(&pid, path, &fileActions, nil, cArgs.map { UnsafeMutablePointer(mutating: $0) }, environ)

        // Close write end in parent
        close(pipeFDs[1])

        guard spawnResult == 0 else {
            close(pipeFDs[0])
            return nil
        }

        // Read stdout from child
        let readFD = pipeFDs[0]
        var data = Data()
        let bufferSize = 256
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while true {
            let bytesRead = read(readFD, buffer, bufferSize)
            if bytesRead <= 0 { break }
            data.append(buffer, count: bytesRead)
        }
        close(readFD)

        // Wait for child
        var status: Int32 = 0
        waitpid(pid, &status, 0)

        guard status == 0 else { return nil }

        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Gets the current monitor brightness as a value from 0.0 to 1.0.
    static func getBrightness() -> CGFloat? {
        guard let output = run(["get", "luminance"]),
              let current = Int(output) else {
            return nil
        }

        let maxValue = getMaxBrightness() ?? 100
        guard maxValue > 0 else { return nil }
        return CGFloat(current) / CGFloat(maxValue)
    }

    /// Gets the maximum brightness value from the display.
    private static func getMaxBrightness() -> Int? {
        guard let output = run(["max", "luminance"]),
              let value = Int(output) else {
            return nil
        }
        return value
    }

    /// Sets the monitor brightness from a value of 0.0 to 1.0.
    @discardableResult
    static func setBrightness(_ value: CGFloat) -> Bool {
        let maxValue = getMaxBrightness() ?? 100
        let clamped = max(0, min(1, value))
        let ddcValue = Int(clamped * CGFloat(maxValue))
        return run(["set", "luminance", "\(ddcValue)"]) != nil
    }
}

#endif
