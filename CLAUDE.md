# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RemindWall is a cross-platform iOS/macOS Catalyst SwiftUI application for managing photo slideshows with reminder tracking for multiple people ("trackees"). It combines photo library management with reminder scheduling, NFC tag scanning, calendar event display, and DDC/CI external monitor brightness control.

**Platforms:** iOS 26+, macCatalyst 26+
**Swift Version:** 6.2 (swift-tools-version 6.3)

## Build and Development

Open `RemindWall.xcodeproj` in Xcode. The project has two app targets:
- **RemindWall** - macOS/macCatalyst target
- **RemindWalliOS** - iOS target

Both targets depend on `RWPureSwift`, a local Swift Package containing all shared code.

### Running Tests

Tests are in `RWPureSwift/Tests/`. Run via Xcode's test navigator or:
- Build/test the full package from the RWPureSwift scheme

### CI Setup

For CI environments, run `ci_scripts/ci_post_clone.sh` to skip macro fingerprint validation (required for Point-Free macro libraries).

## Architecture

The app uses **The Composable Architecture (TCA)** from Point-Free throughout.

### Module Structure (RWPureSwift/Sources/)

**Feature Modules (TCA Reducers):**
- `AppNavigation/` - Top-level navigation between settings and dashboard screens
- `Dashboard/` - Main dashboard combining slideshow, alerts, calendar events, and tag scanning
- `EditSettingsNew/TopLevel/` - Main settings form (album picker, calendar picker, screen off schedule, trackee list)
- `EditSettingsNew/Trackees/` - Trackee CRUD and detail views
- `EditSettingsNew/Reminders/` - Reminder time management per trackee
- `Slideshow/` - Photo gallery with Ken Burns animation and live photo support
- `TagScanner/` - NFC tag reading and association
- `TagScanLoader/` - Bridges tag scanning with the database layer
- `ScreenOffMonitor/` - Scheduled screen dimming based on time-of-day rules

**Data Layer:**
- `Dao/` - SQLite database using Point-Free's `sqlite-data`. Contains schema with `Trackee` and `ReminderTime` tables
- `AppModel/` - App state definitions

**Framework Wrappers:**
- `CalendarAsync/` - EventKit async wrapper
- `PhotoKitAsync/` - Photos framework async wrapper with mock support
- `ScreenControl/` - Screen brightness control (UIKit on iOS, DDC/CI over I2C on macCatalyst for external monitors)

**Shared Types:**
- `AppTypes/` - Core value types: `ReminderPart`, `ScreenOffSchedule`, `CalendarId`, `TagSerial`, `SlotName`, `AlbumLocalId`
- `Utility/` - Small helpers (hex conversion, emoji checking)

### Key Patterns

**TCA Features:** Each feature has a `@Reducer` struct with `State`, `Action`, and `body`. Views take `StoreOf<Feature>` and use `store.scope()` for child features.

**Dependencies:** Use Point-Free's `swift-dependencies`. Access via `@Dependency(\.xxx)`. Test dependencies are configured in test suites using `@Suite(.dependencies { ... })`.

**Database:** SQLite with `@Table` macro for models. Queries use structured queries like `Trackee.all.fetchOne(db)` or `ReminderTime.where { $0.trackeeId == id }.fetchAll(db)`.

**Tagged Types:** IDs use `Tagged<Self, UUID>` for type safety (e.g., `Trackee.ID`, `ReminderTime.ID`).

**Shared State:** Uses `@Shared(.appStorage(...))` for persisted settings that multiple features observe (e.g., screen off schedule, selected album).

### Feature Hierarchy

```
AppNavigationFeature
├── ScreenOffMonitorFeature
├── DashboardFeature
│   ├── SlideShowFeature
│   ├── AlertLoaderFeature
│   ├── CalendarEventsFeature
│   └── TagScanLoaderFeature
└── SettingsFeature (TopLevel)
    ├── AlbumPickerFeature
    ├── CalendarPickerFeature
    ├── ScreenOffSettingFeature
    └── TrackeesFeature
        └── TrackeeDetailFeature
            └── RemindersFeature
                └── AddReminderFeature
```

## Testing Conventions

All code changes should be tested using the "swift test" before any git commits are entered.

Tests use Swift's native `Testing` framework with `@Test` and `@Suite` macros. TCA features are tested with `TestStore`:

```swift
@Suite(.dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
})
struct FeatureTests {
    @Test func testSomething() async {
        let store = TestStore(initialState: Feature.State()) {
            Feature()
        }
        await store.send(.action) { $0.value = expected }
        await store.receive(\.delegateAction)
    }
}
```

## Platform-Specific Notes

- **macCatalyst:** Uses DDC/CI over IOKit's `IOAVService` I2C interface for external monitor brightness control. This requires an external display to be connected; the code guards against crashes when no external monitor is present. Also includes a quit button in settings (macCatalyst only).
- **iOS:** Uses `UIScreen.brightness` for screen control.
- **UI Testing:** Controlled via `UITesting` environment variable; clears UserDefaults and uses in-memory storage.

## Dependencies

- `swift-composable-architecture` - TCA framework
- `swift-dependencies` - Dependency injection
- `sqlite-data` / `swift-structured-queries` - Database layer
- `swift-tagged` - Type-safe identifiers
- `swift-concurrency-deadline` - Async deadline utilities
