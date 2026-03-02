# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RemindWall is a cross-platform iOS/macOS Catalyst SwiftUI application for managing photo slideshows with reminder tracking for multiple people ("trackees"). It combines photo library management with reminder scheduling and NFC tag scanning functionality.

**Platforms:** iOS 26+, macCatalyst 26+
**Swift Version:** 6.2

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
- `EditSettingsNew/TopLevel/` - Main settings form (album picker, calendar picker, trackee list)
- `EditSettingsNew/Trackees/` - Trackee CRUD and detail views
- `EditSettingsNew/Reminders/` - Reminder time management per trackee
- `Slideshow/` - Photo gallery with Ken Burns animation
- `TagScanner/` - NFC tag reading and association

**Data Layer:**
- `Dao/` - SQLite database using Point-Free's `sqlite-data`. Contains schema with `Trackee` and `ReminderTime` tables
- `DataModel/` - Legacy SwiftData models (being phased out)

**Framework Wrappers:**
- `CalendarAsync/` - EventKit async wrapper
- `PhotoKitAsync/` - Photos framework async wrapper with mock support

**Shared Types:**
- `AppTypes/` - Core value types: `ReminderPart`, `DaysOfWeek`, `CalendarId`, `TagSerial`, `SlotName`

### Key Patterns

**TCA Features:** Each feature has a `@Reducer` struct with `State`, `Action`, and `body`. Views take `StoreOf<Feature>` and use `store.scope()` for child features.

**Dependencies:** Use Point-Free's `swift-dependencies`. Access via `@Dependency(\.xxx)`. Test dependencies are configured in test suites using `@Suite(.dependencies { ... })`.

**Database:** SQLite with `@Table` macro for models. Queries use structured queries like `Trackee.all.fetchOne(db)` or `ReminderTime.where { $0.trackeeId == id }.fetchAll(db)`.

**Tagged Types:** IDs use `Tagged<Self, UUID>` for type safety (e.g., `Trackee.ID`, `ReminderTime.ID`).

### Feature Hierarchy

```
SettingsFeature (TopLevel)
├── AlbumPickerFeature
├── CalendarPickerFeature
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

## Dependencies

- `swift-composable-architecture` - TCA framework
- `swift-dependencies` - Dependency injection
- `sqlite-data` / `swift-structured-queries` - Database layer
- `swift-tagged` - Type-safe identifiers
- `swift-concurrency-deadline` - Async deadline utilities
