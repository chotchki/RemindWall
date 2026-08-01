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
- `Dashboard/` - Main dashboard: slideshow + the card rail (`CardModel.swift`, see `SPEC-DASHBOARD.md`) fed by bus/traffic/calendar surfaces, battery chips, med alert overlay, tag scanning
- `EditSettingsNew/TopLevel/` - Main settings form (album picker, calendar picker, screen off schedule, battery alerts, trackee list) plus `SettingsResolver` (syncs album/calendar descriptors to local ids)
- `EditSettingsNew/BusSettings/` - The unified Alerts settings: one watch-list where bus stops and driving routes are peers (per-watch windows + toggles), watch detail, add flows, Setup subscreen (API key + home origin), shared `AlertWindowEditorView`
- `EditSettingsNew/Trackees/` - Trackee CRUD and detail views
- `EditSettingsNew/Reminders/` - Reminder time management per trackee
- `Slideshow/` - Photo gallery with Ken Burns animation and live photo support
- `TagScanner/` - NFC tag reading and association
- `TagScanLoader/` - Bridges tag scanning with the database layer
- `ScreenOffMonitor/` - Scheduled screen dimming based on time-of-day rules

**Data Layer:**
- `Dao/` - SQLite database using Point-Free's `sqlite-data`. Schema: `Trackee`, `ReminderTime`, `Setting` (+ the `.syncedSetting` SharedKey over it), `MonitoredStop`, `MonitoredRoute`
- `AppModel/` - App state definitions

**Framework Wrappers:**
- `CalendarAsync/` - EventKit async wrapper
- `HomeKitAsync/` - HomeKit battery statuses as plain values (live store behind canImport; no HomeKit on pure macOS)
- `PhotoKitAsync/` - Photos framework async wrapper with mock support
- `ScreenControl/` - Screen brightness control (UIKit on iOS, DDC/CI via the ddcd daemon on macCatalyst)
- `TrafficAPI/` - Drive-time ETAs over MKDirections
- `TransitAPI/` - OneBusAway arrivals (API key via `TransitKeyStore`)

**Shared Types:**
- `AppTypes/` - Core value types: `ReminderPart`, `ScreenOffSchedule`, `AlertWindow` (née `BusWindow`), `CalendarId`, `TagSerial`, `SlotName`, `AlbumLocalId`, descriptors (`AlbumDescriptor`, `CalendarDescriptor`, `HomeOrigin`), setting key constants
- `Utility/` - Small helpers (hex conversion, emoji checking)

### Key Patterns

**TCA Features:** Each feature has a `@Reducer` struct with `State`, `Action`, and `body`. Views take `StoreOf<Feature>` and use `store.scope()` for child features.

**Dependencies:** Use Point-Free's `swift-dependencies`. Access via `@Dependency(\.xxx)`. Test dependencies are configured in test suites using `@Suite(.dependencies { ... })`.

**Database:** SQLite with `@Table` macro for models. Queries use structured queries like `Trackee.all.fetchOne(db)` or `ReminderTime.where { $0.trackeeId == id }.fetchAll(db)`.

**Tagged Types:** IDs use `Tagged<Self, UUID>` for type safety (e.g., `Trackee.ID`, `ReminderTime.ID`).

**Shared State:** Portable settings use `@Shared(.syncedSetting(...))` — a custom SharedKey over the CloudKit-synced `settings` table (Dao) — so a change on one device lands on all of them. Device-local values (album/calendar local identifiers) stay on `@Shared(.appStorage(...))` as caches of their synced descriptors.

### Feature Hierarchy

```
AppNavigationFeature
├── ScreenOffMonitorFeature
├── SettingsResolverFeature (descriptor -> local id reconcile)
├── DashboardFeature
│   ├── SlideShowFeature
│   ├── AlertLoaderFeature
│   ├── CalendarEventsFeature
│   ├── BusArrivalsFeature
│   ├── BatteryAlertsFeature
│   ├── TrafficAlertsFeature
│   └── TagScanLoaderFeature
└── SettingsFeature (TopLevel)
    ├── AlbumPickerFeature
    ├── CalendarPickerFeature
    ├── ScreenOffSettingFeature
    ├── BatterySettingsFeature
    ├── AlertsSettingsFeature
    │   ├── WatchDetailFeature
    │   ├── AddMonitoredStopFeature / AddDriveFeature
    │   └── AlertsSetupFeature
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
