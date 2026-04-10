# RemindWall

A cross-platform iOS and macOS (Catalyst) SwiftUI application that turns a device into a smart photo frame with reminder tracking, calendar integration, and NFC tag scanning.

## Features

- **Photo Slideshow** - Select a photo album and display it as a slideshow with Ken Burns animation and live photo support
- **Reminder Tracking** - Track multiple people ("trackees") with configurable reminder schedules and days of the week
- **NFC Tag Scanning** - Associate NFC tags with trackees for quick check-in
- **Calendar Integration** - Display upcoming events from a selected calendar alongside the slideshow
- **Screen Off Scheduling** - Configure automatic screen dimming based on time-of-day rules
- **External Monitor Brightness** - DDC/CI brightness control for external monitors on macCatalyst

## Requirements

- Xcode 26+
- iOS 26+ / macCatalyst 26+
- Swift 6.2

## Getting Started

1. Clone the repository
2. Open `RemindWall.xcodeproj` in Xcode
3. Select the target:
   - **RemindWall** for macOS/macCatalyst
   - **RemindWalliOS** for iOS
4. Build and run

## Project Structure

The app is split into two Xcode app targets that share all code through `RWPureSwift`, a local Swift Package:

```
RemindWall/
├── RemindWall/              # macCatalyst app target
├── RemindWalliOS/           # iOS app target (if present)
└── RWPureSwift/             # Shared Swift Package
    ├── Sources/
    │   ├── AppNavigation/   # Top-level navigation
    │   ├── AppTypes/        # Shared value types
    │   ├── CalendarAsync/   # EventKit async wrapper
    │   ├── Dao/             # SQLite database layer
    │   ├── Dashboard/       # Main dashboard (slideshow + alerts + calendar)
    │   ├── EditSettingsNew/ # Settings UI (album, calendar, trackees, reminders)
    │   ├── PhotoKitAsync/   # Photos framework wrapper
    │   ├── ScreenControl/   # Brightness control (UIKit / DDC-CI)
    │   ├── ScreenOffMonitor/# Scheduled screen dimming
    │   ├── Slideshow/       # Photo slideshow with Ken Burns effect
    │   ├── TagScanLoader/   # NFC tag + database bridge
    │   ├── TagScanner/      # NFC tag reading
    │   └── Utility/         # Small helpers
    └── Tests/
```

## Architecture

Built with [The Composable Architecture (TCA)](https://github.com/pointfreeco/swift-composable-architecture) from Point-Free. Each feature is a `@Reducer` with clearly defined `State`, `Action`, and composition via `Scope` and `store.scope()`.

Key libraries:
- **swift-composable-architecture** - State management and side effects
- **swift-dependencies** - Dependency injection and testability
- **sqlite-data / swift-structured-queries** - Type-safe SQLite database
- **swift-tagged** - Type-safe identifiers
- **swift-concurrency-deadline** - Async timeout utilities

## Testing

Tests use Swift's native `Testing` framework (`@Test`, `@Suite`) and TCA's `TestStore` for feature testing.

```bash
cd RWPureSwift
swift test
```

## License

Private project - all rights reserved.
