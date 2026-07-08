# PLAN.md — Bus Arrivals Feature

## 1. Overview

Add a new "Bus Arrivals" capability to RemindWall that:

1. Lets the user configure an active **time-of-day window** (and weekday selection) during which bus alerts appear on the dashboard.
2. Lets the user configure a list of **monitored stop+route pairs** (e.g. "Route 12 at Main & 5th").
3. Periodically queries a **transit real-time API** using a stored API key.
4. Renders the next arrival(s) for each monitored stop at the **bottom of the slideshow dashboard**, mirroring the visual style of the existing calendar `NowView` / `UpNextView` / `AlertView`.
5. Visually flags **late** buses (predicted arrival is later than the schedule).

Architecture follows the existing TCA + `swift-dependencies` + `sqlite-data` patterns already established in the project — no new architectural primitives.

---

## 2. Goals & Non-Goals

**Goals**
- Window-gated display of real-time bus arrivals on the dashboard.
- Per-stop / per-route monitoring with a small CRUD UI in Settings.
- Reuse the existing time-window UI (clock dial) and dashboard alert visual language.
- All new TCA features fully testable with `TestStore` + a stubbable `TransitAPIClient`.
- Cross-platform (iOS + macCatalyst), no platform-specific code beyond what already exists.
- CloudKit-synced configuration (so iPads around the house stay in lockstep).

**Non-Goals (this iteration)**
- Multiple transit agencies. Initial implementation supports a single agency (the user's local one) configured once.
- Map-based stop discovery. Stops are entered by ID (or selected from a flat list pulled from the agency).
- Push notifications when a bus is late.
- Trip-planning features. We only show "next N arrivals at this stop for this route".
- Auth flows beyond a single static API key.

---

## 3. Decisions (Resolved)

The following were open questions; the user's inline answers (`A:` lines) make them final. Subsequent sections reflect the resolved decisions.

1. **Which transit API?** Most U.S. agencies expose a GTFS-Realtime feed plus a static GTFS dataset for stop/route metadata, but APIs vary widely (511.org, OneBusAway, MTA, MBTA, TransLink, custom agency portals). The shape of `TransitAPIClient` is determined by the agency. **Recommendation:** start with a thin abstraction modelled on a single agency's REST endpoint, leaving the door open to a GTFS-Realtime adapter later. Need from user: agency name, base URL, example endpoint for "stop predictions", and an example response payload.
  - A: I live in seattle, which is pugent sound and they use onebusaway: https://www.soundtransit.org/help-contacts/business-information/open-transit-data-otd

2. **Where does the API key live?**
   - Option A — **Keychain** (`SecItemAdd`, optionally with `kSecAttrSynchronizable` for iCloud Keychain sync). Best for secrets, not visible in plist.
   - Option B — `Setting` SQLite table (already CloudKit-synced via `SyncEngine`). Simple; stored as plaintext in the app's container.
   - Option C — `@Shared(.appStorage(...))`. Stored as plaintext in `UserDefaults`; not synced.
   - **Recommendation:** Option A (Keychain with `kSecAttrSynchronizable`). The Setting table is convenient, but storing a third-party API key as plaintext in a synced SQLite blob is a code-smell that's hard to reverse later.
   - A: Agree on option A

3. **Stop identification model.** A bus stop in most APIs is identified by `(agency, stopId)`. A "monitored entry" usually adds a route filter so we don't show every bus that stops there. **Recommendation:** model a monitored entry as `(stopId, routeId, displayLabel, sortOrder)`. The user gives the display label so they can write "Kids' bus stop" instead of `12345`.
  - A: Agree on the label for the stop, the route should remain as is since peope recognize it.

4. **Late definition.** Two reasonable choices:
   - **Predicted vs scheduled:** the API typically returns both; "late" = `predicted - scheduled > N seconds` (N≈90s).
   - **Predicted vs target arrival window:** the user could configure "the bus we want for school is the 7:42; flag anything > 7:45 as late".
   - **Recommendation:** start with the simpler API-driven definition (predicted - scheduled > 90s shows a "late" badge). Skip per-route target windows initially.
   - A: I'm good with that to start.

5. **Polling cadence.** Real-time feeds churn frequently. **Recommendation:** 30s while inside the active window, no polling outside it. (Calendar feature uses 5s; that's too aggressive against an external rate-limited API.)
   - A: I'm good with 30s unless OneStopAway has something that will cause even less server load.

6. **Time window granularity.** `ScreenOffSchedule` is a single global start/end with no weekday awareness. The user said *"during the week"* — so we likely want per-weekday selection (mask of which days the window is active) plus a single start/end. **Recommendation:** add a weekday mask; default = Mon–Fri.
   - A: I'm fine with that.

---

## 4. Architecture Overview

The feature spans four layers, all matching existing patterns:

| Layer | New module | Mirrors existing |
|---|---|---|
| Shared types | `AppTypes/BusWindow.swift`, `AppTypes/StopId.swift`, `AppTypes/RouteId.swift` | `ScreenOffSchedule`, `CalendarId`, `TagSerial` |
| External I/O wrapper | `TransitAPI/` (new package target) | `CalendarAsync`, `PhotoKitAsync` |
| Persistence | New tables `monitoredStops` (+ migration) in `Dao/Schema.swift` | `Trackee`, `ReminderTime` |
| TCA features | `BusArrivals/` (dashboard widget) and additions inside `EditSettingsNew/TopLevel/` | `Dashboard/CalendarEvents.swift` + `EditSettingsNew/TopLevel/CalendarPicker.swift` |

Feature tree after the change:

```
AppNavigationFeature
├── ScreenOffMonitorFeature
├── DashboardFeature
│   ├── SlideShowFeature
│   ├── AlertLoaderFeature
│   ├── CalendarEventsFeature
│   ├── BusArrivalsFeature        ← NEW
│   └── TagScanLoaderFeature
└── SettingsFeature (TopLevel)
    ├── AlbumPickerFeature
    ├── CalendarPickerFeature
    ├── ScreenOffSettingFeature
    ├── BusSettingsFeature        ← NEW (toggle + window + key + stops list)
    │   └── MonitoredStopsFeature ← NEW
    │       └── AddMonitoredStopFeature
    └── TrackeesFeature
```

---

## 5. Data Model

### 5.1 New SQLite table — `monitoredStops`

In `RWPureSwift/Sources/Dao/Schema.swift`, alongside the existing `@Table` structs:

```swift
@Table
public nonisolated struct MonitoredStop: Equatable, Identifiable, Sendable {
    public typealias ID = Tagged<Self, UUID>
    public let id: ID
    public var label: String           // user-facing, e.g. "School bus"
    public var stopId: String          // agency stop id
    public var routeId: String         // agency route id
    public var routeShortName: String  // "12", "Express", etc. — cached from agency
    public var sortOrder: Int          // for display ordering
}
```

Add a migration block in `appDatabase()`:

```swift
migrator.registerMigration("Create monitoredStops table") { db in
    try #sql("""
      CREATE TABLE "monitoredStops" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "label" TEXT NOT NULL,
        "stopId" TEXT NOT NULL,
        "routeId" TEXT NOT NULL,
        "routeShortName" TEXT NOT NULL,
        "sortOrder" INTEGER NOT NULL DEFAULT 0
      )
      """).execute(db)
}
```

Register it with `SyncEngine` in `appSyncEngine(for:)`:

```swift
try SyncEngine(
    for: database,
    tables: Trackee.self, ReminderTime.self, Setting.self, MonitoredStop.self
)
```

### 5.2 Configuration

| Setting | Storage | Why |
|---|---|---|
| `busAlertsEnabled` (Bool) | `@Shared(.appStorage("busAlertsEnabled"))` | Same approach as the slideshow / calendar / screen-off toggles |
| `busWindow` (`BusWindow` value) | `@Shared(.appStorage("busWindow"))` | Cheap, observable, matches `ScreenOffSchedule` pattern |
| `busApiKey` (String) | **Keychain** (`kSecAttrSynchronizable: true`) | Recommendation #2 above. Encapsulated behind a `@Dependency(\.transitKeyStore)` client to keep the rest of the code testable. |

### 5.3 New `AppTypes/BusWindow.swift`

```swift
public enum BusWindowTag {}
public typealias BusWindow = Tagged<BusWindowTag, String>

extension BusWindow {
    // Encoding: "<weekdayMask>|<startHour>:<startMin>-<endHour>:<endMin>"
    // weekdayMask: 7-bit mask, bit 0 = Sunday (matches DaysOfWeek.rawValue ordering)
    public init(weekdays: Set<DaysOfWeek>,
                startHour: Int, startMinute: Int,
                endHour: Int,  endMinute: Int)
    public var weekdays: Set<DaysOfWeek> { ... }
    public var startHour: Int { ... } // etc.
    public func isInWindow(date: Date, calendar: Calendar) -> Bool
    public static let `default` = BusWindow(
        weekdays: [.Monday, .Tuesday, .Wednesday, .Thursday, .Friday],
        startHour: 6, startMinute: 30,
        endHour: 9,   endMinute: 0
    )
}
```

The string encoding mirrors `ScreenOffSchedule`'s split-on-delimiter approach so we get cheap `@Shared(.appStorage)` storage with no `Codable` ceremony. New `SETTING_KEY` constants go in `AppTypes/SettingConstants.swift`:

```swift
public let BUS_WINDOW_SETTING_KEY = "busWindow"
public let BUS_ALERTS_ENABLED_SETTING_KEY = "busAlertsEnabled"
```

---

## 6. Dependency Layer — `TransitAPI` (OneBusAway / Sound Transit)

New Swift Package target `TransitAPI`, depending only on `Dependencies`, `DependenciesMacros`, and `AppTypes`. Models OneBusAway's "Where API" exactly like `CalendarAsync` models EventKit.

### 6.1 Constants & quirks of OBA

- **Base URL:** `https://api.pugetsound.onebusaway.org` (Puget Sound regional server; the legacy `api.onebusaway.org` is deprecated).
- **API key acquisition:** the user emails `oba_api_key@soundtransit.org`. We don't automate this — the Settings UI just shows a "Need a key?" link with `mailto:` prefilled.
- **Auth:** query-string `?key=...` only. Authorization header silently 401s.
- **Rate limit:** 100ms minimum between requests on a default key; 401 on violation. Our 30s polling per stop is well clear of this, but the client should still serialize concurrent calls through a small actor to stay safe if the user adds many monitored stops.
- **No SSE / WebSocket / ETag.** Plain request/response only. 30s polling is consistent with what OBA's own iOS/Android apps use.
- **ID format:** `agencyId_localId` (e.g. `1_75403` = King County Metro stop 75403, `40_100479` = Sound Transit). Stored as plain `String`, not `Tagged`, since the embedded prefix is meaningful.
- **Times:** all `Long` ms-since-epoch UTC. `predictedArrivalTime == 0` is the sentinel for "no real-time prediction" — never display 1970-01-01.
- **Real-time gate:** an arrival is "live" iff `predicted == true && predictedArrivalTime != 0`. Otherwise fall back to `scheduledArrivalTime` and dim the row.
- **Route filtering on arrivals is client-side.** `arrivals-and-departures-for-stop` does not accept a `routeId` filter; we fetch all arrivals for the stop and filter ourselves. Two monitored entries that share a `stopId` should coalesce to a single network call (de-dup before the fan-out).

### 6.2 Endpoints we use

All under `/api/where/...`, JSON suffix, query-string `?key=...`.

| Endpoint | Path | Used by |
|---|---|---|
| Validate stop + list its routes | `/api/where/stop/{stopId}.json` | Add-Stop UI: confirms the user-typed code and gives us `routeIds` to populate the route picker |
| Lookup route metadata | `/api/where/route/{routeId}.json` | One-off when saving a monitored stop, so we cache `routeShortName` |
| Live arrivals for a stop | `/api/where/arrivals-and-departures-for-stop/{stopId}.json` | Hot polling path; we client-side filter to the configured `routeId` |
| Sanity check / future expansion | `/api/where/agencies-with-coverage.json` | "Test connection" button in Settings |

### 6.3 Swift client shape

```swift
// Sources/TransitAPI/Models.swift
public struct StopInfo: Equatable, Sendable {
    public let stopId: String      // "1_75403"
    public let code: String        // "75403" (what's printed on the sign)
    public let name: String
    public let routeIds: [String]  // routes that serve this stop
}

public struct RouteInfo: Equatable, Sendable {
    public let routeId: String     // "1_100224"
    public let shortName: String   // "12"
    public let longName: String    // "Capitol Hill - Downtown"
    public let agencyId: String    // "1"
}

public struct ArrivalPrediction: Equatable, Sendable {
    public let stopId: String
    public let routeId: String
    public let tripId: String
    public let tripHeadsign: String
    public let scheduledArrival: Date?   // nil if scheduledArrivalTime == 0
    public let predictedArrival: Date?   // nil if predictedArrivalTime == 0
    public let isPredicted: Bool         // OBA's `predicted` flag
    public let lastUpdate: Date?
    /// The arrival time we should display: predicted if available, else scheduled.
    public var effectiveArrival: Date? { predictedArrival ?? scheduledArrival }
    /// True iff we have a real-time prediction.
    public var isLive: Bool { isPredicted && predictedArrival != nil }
    /// Seconds late vs schedule; nil if either time is missing.
    public var lateness: TimeInterval? {
        guard let p = predictedArrival, let s = scheduledArrival else { return nil }
        return p.timeIntervalSince(s)
    }
}
```

```swift
// Sources/TransitAPI/TransitAPIClient.swift
@DependencyClient
public struct TransitAPIClient: Sendable {
    /// Hot path. Returns *all* arrivals at the stop in the next ~35 minutes.
    /// Caller filters to the desired routeId.
    public var fetchArrivals: @Sendable (
        _ apiKey: String,
        _ stopId: String
    ) async throws -> [ArrivalPrediction]

    /// Used by Add-Stop UI to validate a user-entered stop code and fetch its routes.
    public var fetchStop: @Sendable (
        _ apiKey: String,
        _ stopId: String
    ) async throws -> StopInfo

    /// Used by Add-Stop UI to render route names in the route picker.
    public var fetchRoute: @Sendable (
        _ apiKey: String,
        _ routeId: String
    ) async throws -> RouteInfo

    /// Used by the Settings "Test connection" button.
    public var testConnection: @Sendable (_ apiKey: String) async throws -> Void
}
```

Notes on the `liveValue`:
- One small `actor` rate-gate inside the client serializes outbound requests to be ≥ 110ms apart, so concurrent fan-out (a `withThrowingTaskGroup` over many stops) can't trip the 100ms 401.
- JSON decoding uses standard `Decodable` against an internal `OBAResponse<Entry>` envelope (`{ code, currentTime, data: { entry, references } }`).
- A typed `TransitAPIError` enum surfaces `.unauthorized` (401), `.rateLimited`, `.notFound`, `.network(Error)`, `.decoding(Error)` so the UI can render specific messages.
- Bundled JSON fixtures under `Tests/TransitAPITests/Fixtures/` exercise decoding.

### 6.4 Keychain client

```swift
@DependencyClient
public struct TransitKeyStore: Sendable {
    public var read:  @Sendable () -> String?
    public var write: @Sendable (String?) -> Void
}
```

`liveValue` uses `SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete` with `kSecAttrSynchronizable: true` (iCloud Keychain). Service: app bundle id, account: `"oba_api_key"`. `testValue` uses an in-memory `LockIsolated<String?>`.

Both clients register `extension DependencyValues` accessors (`\.transitAPI`, `\.transitKeyStore`).

---

## 7. Feature Modules

### 7.1 `BusArrivalsFeature` (Dashboard widget)

Lives in `RWPureSwift/Sources/Dashboard/BusArrivals.swift` (same module as `CalendarEvents.swift`; no new package target needed). Modeled closely on `CalendarEventsFeature`:

```swift
@Reducer
public struct BusArrivalsFeature: Sendable {
    @Dependency(\.transitAPI) var transitAPI
    @Dependency(\.transitKeyStore) var transitKeyStore
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    @Dependency(\.calendar) var calendar

    static let refreshInterval = Duration.seconds(30)

    @ObservableState
    public struct State: Equatable {
        @Shared(.appStorage(BUS_ALERTS_ENABLED_SETTING_KEY)) var enabled: Bool = false
        @Shared(.appStorage(BUS_WINDOW_SETTING_KEY))        var window: BusWindow?

        @FetchAll(MonitoredStop.none)
        var monitoredStops: [MonitoredStop]

        public var arrivals: [DisplayArrival] = []   // joined view-model
        public var inWindow: Bool = false
        public var lastError: String? = nil

        public init() {
            self._monitoredStops = FetchAll(MonitoredStop.all.order(by: \.sortOrder))
        }
    }

    public enum Action: Equatable {
        case startMonitoring
        case tick
        case _arrivalsLoaded([DisplayArrival], inWindow: Bool, error: String?)
    }
    enum CancelID { case busLoop }

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .startMonitoring:
                return .run { send in
                    await send(.tick)
                    for await _ in clock.timer(interval: Self.refreshInterval) {
                        await send(.tick)
                    }
                }.cancellable(id: CancelID.busLoop, cancelInFlight: true)

            case .tick:
                let inWindow = state.window?.isInWindow(date: now, calendar: calendar) ?? false
                guard state.enabled, inWindow,
                      let key = transitKeyStore.read(),
                      !state.monitoredStops.isEmpty
                else {
                    return .send(._arrivalsLoaded([], inWindow: inWindow, error: nil))
                }
                let stops = state.monitoredStops
                // Coalesce by stopId: OBA returns all routes for a stop in one call,
                // so two monitored entries sharing a stopId only need one network request.
                let uniqueStopIds = Array(Set(stops.map(\.stopId)))
                return .run { send in
                    do {
                        // Fetch arrivals once per unique stopId.
                        let byStop = try await withThrowingTaskGroup(
                            of: (String, [ArrivalPrediction]).self
                        ) { group in
                            for stopId in uniqueStopIds {
                                group.addTask {
                                    let arrivals = try await transitAPI.fetchArrivals(
                                        apiKey: key, stopId: stopId
                                    )
                                    return (stopId, arrivals)
                                }
                            }
                            return try await group.reduce(into: [String: [ArrivalPrediction]]()) {
                                $0[$1.0] = $1.1
                            }
                        }
                        // Filter each monitored entry to its routeId, take soonest arrival.
                        let display = stops.compactMap { stop -> DisplayArrival? in
                            let arrivals = (byStop[stop.stopId] ?? [])
                                .filter { $0.routeId == stop.routeId }
                                .sorted { ($0.effectiveArrival ?? .distantFuture)
                                       < ($1.effectiveArrival ?? .distantFuture) }
                            return makeDisplay(stop: stop, soonest: arrivals.first, now: now)
                        }
                        await send(._arrivalsLoaded(display, inWindow: true, error: nil))
                    } catch {
                        await send(._arrivalsLoaded([], inWindow: true, error: "\(error)"))
                    }
                }

            case let ._arrivalsLoaded(arrivals, inWindow, error):
                state.arrivals = arrivals
                state.inWindow = inWindow
                state.lastError = error
                return .none
            }
        }
    }
}

public struct DisplayArrival: Equatable, Identifiable, Sendable {
    public let id: MonitoredStop.ID
    public let label: String           // user's display name
    public let routeShortName: String
    public let etaText: String         // "in 4 min"
    public let isLate: Bool            // lateness > 90s vs schedule
    public let isLive: Bool            // dim if scheduled-only
}
```

Notes:
- `@FetchAll` on `MonitoredStop` makes the widget reactive to CloudKit-driven changes (same pattern as `AlertLoaderFeature`).
- `makeDisplay(stop:soonest:now:)` is a pure helper, so the formatting and "is late" logic are unit-testable without `TestStore`. Late = `lateness > 90` seconds.
- A network failure populates `lastError` but doesn't crash; the widget renders an unobtrusive `⚠` chip rather than going silent (so a wall iPad shows the API outage at a glance).
- The `@Dependency(\.transitKeyStore).read()` call in `.tick` is synchronous; tests inject `LockIsolated`-backed stubs.

### 7.2 Dashboard integration

In `Dashboard/DashboardView.swift`:

- Add `var busArrivalsState = BusArrivalsFeature.State()` to `DashboardFeature.State`.
- Add a `case busArrivals(BusArrivalsFeature.Action)` and `Scope` in the body.
- Fire `.send(.busArrivals(.startMonitoring))` from `.onAppear`.
- In `DashboardView.body`'s `ZStack`, place a new `BusArrivalsBar` view at the bottom edge:

```swift
VStack {
    Spacer()
    if !store.busArrivalsState.arrivals.isEmpty {
        BusArrivalsBar(arrivals: store.busArrivalsState.arrivals)
            .transition(.move(edge: .bottom))
    }
}
```

The existing `AlertView` (red overdue meds banner) overlays everything — that is intentional; bus info should *not* compete with a missed-meds emergency. We render the bus bar above the slideshow but below the alert overlay.

### 7.3 `BusSettingsFeature` (Settings screen)

New file `EditSettingsNew/TopLevel/BusSettings.swift`. Owns:

- The "Bus Alerts" master toggle (`busAlertsEnabled`).
- Sub-section: API key entry (`SecureField` bound through `transitKeyStore`).
- Sub-section: window picker — reuses `ClockDialView` + adds a weekday `Picker`/multi-toggle row.
- Sub-section: monitored stops list → pushes to `MonitoredStopsView`.

Rough shape, copying the `ScreenOffSettingFeature` template:

```swift
@Reducer
public struct BusSettingsFeature {
    @Dependency(\.transitKeyStore) var transitKeyStore
    @Dependency(\.transitAPI) var transitAPI

    @ObservableState
    public struct State: Equatable {
        @Shared(.appStorage(BUS_ALERTS_ENABLED_SETTING_KEY)) var enabled: Bool = false
        @Shared(.appStorage(BUS_WINDOW_SETTING_KEY)) var window: BusWindow?
        public var apiKeyDraft: String = ""
        public var monitoredStopsState = MonitoredStopsFeature.State()
        public init() {}
    }

    public enum Action {
        case onAppear
        case enabledToggled(Bool)
        case setWindow(BusWindow)
        case toggleWeekday(DaysOfWeek)
        case apiKeyChanged(String)
        case saveApiKey
        case monitoredStops(MonitoredStopsFeature.Action)
    }
    // body: standard reducer, enabledToggled flips $enabled, setWindow/toggleWeekday rewrite $window
}
```

The view is rendered as a `Section` in the existing `SettingsView` `Form`, alongside the Slideshow / Calendar / Screen Off / Trackees sections. The `Toggle` header + body pattern is identical to those sections.

### 7.4 `MonitoredStopsFeature` (CRUD list)

Mirrors `RemindersFeature` (`EditSettingsNew/Reminders/Reminders.swift`) closely:

- `@FetchAll(MonitoredStop.all.order(by: \.sortOrder))`.
- Delete row → `MonitoredStop.find(id).delete().execute(db)`.
- "Add" sheet presents `AddMonitoredStopFeature` (mirrors `AddReminderFeature`).

`AddMonitoredStopFeature` UX (driven by OBA's structure — there's no "list all stops" picker because Puget Sound has tens of thousands):

1. User types the stop code from the bus stop sign (e.g. `75403`) plus an agency prefix selector (defaults to King County Metro `1`). We compose `1_75403`.
2. User taps "Look up". We call `transitAPI.fetchStop(apiKey, stopId)`.
   - Success: show the canonical stop name returned by OBA and populate a route `Picker` from `StopInfo.routeIds`. For each route id, lazily fire `transitAPI.fetchRoute` to get its `shortName`/`longName` for display.
   - 401 / 404 / network error: show inline error with "Check your API key" / "Stop not found" guidance.
3. User picks the route, types a label (defaults to the OBA-returned stop name), taps Save.
4. Reducer assembles a `MonitoredStop.Draft` and emits `delegate(.saveStop(draft))`, mirroring `AddReminderFeature`'s save flow.

### 7.5 New package target wiring (`Package.swift`)

```swift
.library(name: "TransitAPI", targets: ["TransitAPI"]),

.target(name: "TransitAPI", dependencies: [
    .product(name: "Dependencies", package: "swift-dependencies"),
    .product(name: "DependenciesMacros", package: "swift-dependencies"),
    .target(name: "AppTypes"),
]),
.testTarget(name: "TransitAPITests", dependencies: [
    "TransitAPI",
    .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
]),

// Add TransitAPI to:
// - Dashboard target (for BusArrivalsFeature)
// - EditSettingsNew_TopLevel target (for BusSettingsFeature + AddMonitoredStop pickers)
// Add Dao to those if not already present.
```

Add `BusWindow.swift` to `AppTypes`. Stop and route IDs stay as plain `String` since OBA's `agencyId_localId` format is meaningful prefix-encoded data — `Tagged` would obscure the embedded agency id without giving us type-safety we'd actually use.

---

## 8. UI Plan

### 8.1 Settings — new section in `SettingsView`

```
Form
├── Slideshow             (existing)
├── Calendar Reminders    (existing)
├── Screen Off            (existing)
├── Bus Alerts            ← NEW
│   ├── Toggle header
│   ├── API Key (SecureField, "Save" button when dirty)
│   │     + "Get a key" link (mailto:oba_api_key@soundtransit.org)
│   ├── Window
│   │   ├── ClockDialView (start/end)
│   │   └── Weekday row of toggles (S M T W T F S)
│   ├── Monitored Stops → NavigationLink to list
│   └── Test connection button (calls testConnection → agencies-with-coverage)
├── Trackees              (existing)
├── Version
└── Quit (Catalyst)
```

### 8.2 Monitored Stops list (push)

```
List of MonitoredStop rows:
┌──────────────────────────────────────┐
│  [12]  School bus — Main & 5th    🗑 │
│  [22]  Wife's commute — Oak St    🗑 │
└──────────────────────────────────────┘
                                     [+]
```

`+` opens `AddMonitoredStopView` as a sheet.

### 8.3 Add Monitored Stop sheet

```
Form
├── Agency       [Picker — King County Metro / Sound Transit / Pierce / …]
├── Stop code    [TextField "75403"]   [Look up]
│     → on success: shows OBA stop name (e.g. "3rd Ave & Pike St")
├── Route        [Picker — populated from fetched StopInfo.routeIds]
├── Label        [TextField, defaults to stop name]
└── [Cancel]              [Save]
```

If lookup fails (no API key → 401, stop not found → 404, network), show an inline message with the specific cause and an action to fix it (open Settings, retry, etc.).

The Agency picker is a small hardcoded list keyed off the Puget Sound region's documented agency IDs (`1` King County Metro, `3` Pierce Transit, `19` Intercity Transit, `20` Kitsap Transit, `23` City of Seattle, `29` Community Transit, `40` Sound Transit, `95` WSF, `97` Everett Transit). This avoids a second API roundtrip and matches what's printed on the rider-facing signage.

### 8.4 Dashboard — `BusArrivalsBar`

Bottom-anchored horizontal bar. One card per monitored stop:

```
┌────────────────────────────────────────────────────────┐
│  [12]  School bus     in 4 min  •  on time             │
│  [22]  Wife's commute in 12 min •  ⚠ 3 min late        │
└────────────────────────────────────────────────────────┘
```

- Route badge uses a colored pill, reading `routeShortName`.
- ETA computed from `effectiveArrival - now` (predicted if available, else scheduled), formatted with `DateComponentsFormatter` (same pattern as `CalendarEventsFeature`'s next-event time).
- Late state: `predictedArrival - scheduledArrival > 90s`. Red badge, `⚠`, "N min late".
- If `isLive == false` (no real-time prediction — `predicted == false` or `predictedArrivalTime == 0`), italicize and dim the row, prefix the ETA with "scheduled".
- If `lastError != nil` and arrivals empty, render a small `⚠ Cannot reach transit API` chip rather than nothing — failure should be visible at a glance on a wall iPad.

Fits beneath the existing calendar `UpNextView` (which is also bottom-anchored). Lay them out in the same `VStack { Spacer(); UpNextView; BusArrivalsBar }` so they stack predictably.

---

## 9. Test Strategy

Follow the existing test conventions (Swift Testing `@Test` / `@Suite`, `TestStore`, `withDependencies`, `TestClock`).

### 9.1 New test files

| Suite | What it covers |
|---|---|
| `AppTypesTests/BusWindowTests` | encoding round-trip, `isInWindow` for same-day/overnight/non-window weekdays/edge minutes, `default` value sanity |
| `DaoTests/SchemaTests` (extend) | `MonitoredStop` insert + fetch + delete; `INSERT OR REPLACE` doesn't drop other rows; sync-table list contains `MonitoredStop.self` |
| `TransitAPITests` | OBA JSON envelope decoding from bundled fixtures for `arrivals-and-departures-for-stop`, `stop`, `route`, `agencies-with-coverage`; sentinel handling (`predictedArrivalTime == 0` → `nil`); error mapping (401 → `.unauthorized`, 404 → `.notFound`); rate-gate spacing test using `TestClock` |
| `DashboardTests/BusArrivalsTests` | `startMonitoring` immediate tick + loop; tick outside window clears arrivals; tick inside window dedupes by `stopId`; client-side route filter picks correct arrival; error path renders `lastError`; `_arrivalsLoaded` updates state |
| `EditSettingsNew_TopLevelTests/BusSettingsTests` | toggle on/off, weekday toggle round-trip, save API key calls `transitKeyStore.write`, "Test connection" surfaces success / 401 |
| `EditSettingsNew_TopLevelTests/MonitoredStopsTests` | add/delete round-trips through the database; `@FetchAll` re-load; AddMonitoredStop lookup happy path + 404 path |

Patterns to mirror specifically:
- **Time-window logic** → copy the table-driven approach in `ScreenOffScheduleTests`.
- **Reactive widget** → copy `AlertLoaderTests.reminderLifecycle` for "config changes → next tick reflects".
- **Async loop** → copy `CalendarEventsTests.startMonitoring` (`store.exhaustivity = .off`, then `await store.receive(\.tick)` etc.).
- **Stub the API** → in `TestStore`'s `withDependencies`, set `$0.transitAPI.fetchArrivals = { _, _ in [...] }` (per-method overrides — same pattern `CalendarAsync` tests use).
- **JSON fixtures** → bundle representative OBA responses under `Tests/TransitAPITests/Fixtures/*.json` (one per endpoint), loaded via `Bundle.module.url(forResource:withExtension:)`. Mirrors how `Slideshow` ships preview assets.

### 9.2 Manual / UI testing

CLAUDE.md requires running `swift test` before commits. For UI verification, per `CLAUDE.md`'s instruction "if you can't test the UI, say so explicitly" — manual verification will be required:

1. Configure a real API key, real stop, real route.
2. Verify the bar shows predictions on an iPad.
3. Validate that turning the master toggle off hides the bar.
4. Validate that being outside the window hides the bar.

---

## 10. Implementation Order

Each phase ends in a green `swift test` run.

1. **Types + storage primitives** (no UI yet)
   - Add `BusWindow` to `AppTypes` + tests.
   - Add `MonitoredStop` `@Table`, migration, sync registration in `Dao` + tests.
   - Add `BUS_*_SETTING_KEY` constants.

2. **Transit API package**
   - Stand up the `TransitAPI` target, `TransitAPIClient`, `TransitKeyStore`.
   - Implement `liveValue` against `https://api.pugetsound.onebusaway.org/api/where/...` with the rate-gate actor.
   - Bundle representative OBA JSON fixtures and exercise the decoder.

3. **Settings UI**
   - `BusSettingsFeature` reducer + view (master toggle, API key field, window picker, weekday row, "Test connection" button).
   - `MonitoredStopsFeature` + `AddMonitoredStopFeature` (CRUD).
   - Wire into `SettingsView`.
   - Tests for each reducer.

4. **Dashboard widget**
   - `BusArrivalsFeature` reducer.
   - `BusArrivalsBar` view.
   - Wire into `DashboardFeature` / `DashboardView`.
   - Tests covering window gating, error display, late detection.

5. **Polish**
   - Manual end-to-end on iPad.
   - Decide whether to also gate the screen-off behavior on bus-arrival presence (currently `ScreenOffMonitorFeature` ignores everything except late reminders — should an incoming bus also wake the screen? Probable answer: yes if late, no otherwise. Add `hasBusAlerts` channel similar to `hasLateReminders`).

---

## 11. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| OBA 100ms rate limit → 401 spam | Internal `actor` rate-gate inside `TransitAPIClient` ensures ≥110ms spacing across all callers, even when fanning out a `withThrowingTaskGroup`. De-dup monitored entries by `stopId` so two routes at one stop = one network call. 30s polling adds another safety margin. |
| API key delivery delay (Sound Transit can take days to issue a key) | Phase 2 is independently testable with the documented `key=TEST` low-volume key. Productionize once the real key arrives. |
| API key leakage via screenshots / sync logs | Keychain with `kSecAttrSynchronizable`; never log the key value; mask in `SecureField`; never include the key string in error messages surfaced to UI (use `TransitAPIError.unauthorized` instead). |
| OBA `predictedArrivalTime == 0` rendered as 1970-01-01 | Decoder maps `0` to `nil`; `effectiveArrival` falls back to `scheduledArrival`; `isLive` short-circuits the late check. Covered by a fixture-based decoder test. |
| OBA returns multiple imminent arrivals; we pick the wrong one | Sort by `effectiveArrival ascending`, take `.first`. Document that the bar shows the *next* arrival, not "the bus we want for school" — that's a deferred enhancement (§12). |
| Wall-clock skew on the iPad showing "5 min late" because the device clock is wrong | `@Dependency(\.date.now)` already gives us a single seam; not a code risk, but worth noting in the README. OBA also returns `currentTime` per response — we could compute ETAs against that instead of local clock to harden against drift, deferred unless a problem appears. |
| `@FetchAll` + CloudKit sync timing — newly-synced `MonitoredStop` may not be visible until next observation | Already proven to work for `Trackee`/`ReminderTime`; rely on the same machinery. |
| Visual conflict between bus bar and `UpNextView` calendar widget | Both are `Spacer + bottom`. Stack them in a single `VStack` so they coexist; iterate after seeing it on the wall. |

---

## 12. Future Enhancements (explicitly deferred)

- Per-route target arrival ("7:42 bus") with custom late thresholds.
- Multiple agencies / multiple API keys.
- Map-based stop picker.
- Push notifications when a bus is late or missed.
- GTFS-Realtime adapter for protobuf feeds.
- Service-alert ingestion (route closures, detours).
- Per-trackee bus assignments (e.g. show the kid's name next to their bus).

---

## 13. Files Touched / Created (summary)

**Created**
- `RWPureSwift/Sources/AppTypes/BusWindow.swift`
- `RWPureSwift/Sources/TransitAPI/Models.swift`
- `RWPureSwift/Sources/TransitAPI/TransitAPIClient.swift` (live + test + preview)
- `RWPureSwift/Sources/TransitAPI/TransitAPIError.swift`
- `RWPureSwift/Sources/TransitAPI/TransitKeyStore.swift`
- `RWPureSwift/Sources/Dashboard/BusArrivals.swift`
- `RWPureSwift/Sources/Dashboard/Widgets/BusArrivalsBar.swift`
- `RWPureSwift/Sources/EditSettingsNew/TopLevel/BusSettings.swift`
- `RWPureSwift/Sources/EditSettingsNew/TopLevel/WeekdayPicker.swift`
- `RWPureSwift/Sources/EditSettingsNew/MonitoredStops/MonitoredStops.swift` (new sub-folder)
- `RWPureSwift/Sources/EditSettingsNew/MonitoredStops/AddMonitoredStop.swift`
- `RWPureSwift/Tests/TransitAPITests/Fixtures/*.json` (one fixture per OBA endpoint we consume)
- Tests for each of the above per §9.

**Modified**
- `RWPureSwift/Package.swift` — new `TransitAPI` target + library, new `EditSettingsNew_MonitoredStops` target, new dependencies on `Dashboard`, `EditSettingsNew_TopLevel`.
- `RWPureSwift/Sources/Dao/Schema.swift` — `MonitoredStop` table, migration, `SyncEngine` table list.
- `RWPureSwift/Sources/AppTypes/SettingConstants.swift` — new keys.
- `RWPureSwift/Sources/Dashboard/DashboardView.swift` — wire in `BusArrivalsFeature`.
- `RWPureSwift/Sources/EditSettingsNew/TopLevel/Settings.swift` — wire in `BusSettingsFeature` section.

---

# RemindWall Active Phases

Phase N1 (NFC scan reliability) completed 2026-07-03 → swept to PLAN_ARCHIVE.md.

Context that outlives N1: screen-off findings from the scan audit are LIVE on current deploys (ScreenOffMonitor works on the iPads and the unsandboxed Mac) — a scan during the off-window renders its overlay on a dark panel, and scanning a late reminder at night triggers re-dim within 0-35s of the tap. N1.11's sounds cover the feedback gap; wake-on-scan sits in Backlog until T1 lands displayOn().

## Phase T1 - Sandboxed Mac TestFlight via local DDC daemon

Why this phase: TestFlight for Mac hard-rejects unsandboxed builds at upload (ITMS-90296, before any human review), and no exception entitlement gets a DDC path through the sandbox — every shipping DDC app (MonitorControl, Lunar, BetterDisplay) distributes outside the store for exactly this reason. So the DDC work moves OUT of the app into `ddcd/`, a small Rust daemon living as a new top-level crate in this repo; the sandboxed app talks to it over 127.0.0.1 (needs only `network.client`, which bus arrivals already requires). Every device stays on TestFlight's update pipeline, and the daemon rides launchd next to the other servers already on the kiosk box.

NSUserUnixTask was the first candidate and IS workable (audit prototype proved runtime reachability from Catalyst and review-cleanliness), but it taxes every call with bash-watchdog + ObjC-runtime glue: no timeout/kill API on a hung task, execute-at-most-once instances that crash uncatchably on reuse, exit statuses collapsed into a localized string, parallel XPC execution colliding on the single-master I2C bus. The daemon turns all of that into ordinary server code (URLSession timeout, a mutex, HTTP statuses, KeepAlive). Review note: App Review's machines won't have the daemon, so the app must present fully functional without it — availability gating covers this. Honest cost of the TestFlight route on an always-on kiosk: builds EXPIRE after 90 days, and an expired build refuses to relaunch — a crash past day 90 with no fresh build shipped means a dead kiosk (the iPads already live on this treadmill, so it's a known cadence, but the Mac's KeepAlive relaunch agent turns "app crashed" into "app relaunched with an expired build" if the treadmill slips). Last-resort fallback: Developer ID + notarization (sandbox optional, but loses TestFlight updates).

The daemon also unblocks TRUE monitor off/on — the original goal, tried three times before (git: IODisplayConnect via dlsym, dead API on Apple Silicon; in-process IOAVService, flagged by App Review; m1ddc spawn, luminance only). The new option: OS-level display sleep (`pmset displaysleepnow`) with an OS-level wake (IOPMAssertionDeclareUserActivity) — the panel enters real standby on signal loss and wakes on signal return, so the wake path never depends on a DDC command reaching a sleeping monitor. Ordering constraint either way: DDC is dead while the panel sleeps, so wake -> wait for the AV service -> reassert luminance. T1.2 probes the kiosk monitor to pick the mechanism.

- [x] T1.1 - `ddcd/` Rust crate: axum bound to 127.0.0.1 (configurable port — the box also runs hotchkiss.io and friends), GET /health, GET /brightness, PUT /brightness (0.0-1.0); require a custom request header + reject CORS preflight (localhost is NOT a trust boundary on a box serving public traffic — this kills browser CSRF outright); m1ddc invocations behind a mutex with a per-call process timeout (~5s kill); unit tests against a fake m1ddc
- [x] T1.2 - Hardware probe on the kiosk monitor (decides T1.3's mechanism): (a) `pmset displaysleepnow` + `caffeinate -u -t 2` wake — verify unprivileged, panel truly off, wake latency; (b) VCP D6 standby via m1ddc + DDC wake — does the monitor ACK while asleep; measure how long the AV service takes to return after wake either way
  - v1 run (2026-07-03, Hearthstone / LG HDR 4K over USB-C): route (b) UNAVAILABLE — brew m1ddc 1.2.0 has no `set power` (HEAD-only feature, probe falsely reported it passing); DDC READS corrupted (luminance -51 / max 62); test (a) visually unconfirmed. Probe v2 adds exit-code honesty, a read-stability check, a sleep-transition DDC timeline + captured eyeball observations — re-run 2026-07-03: B confirmed (visible off+on via SSH, unprivileged); reads 100% corrupted even with RemindWall quit -> Mac path goes WRITE-ONLY (T1.13); DDC ACKs throughout sleep so no wake-wait needed
- [x] T1.13 - Restore-to-configured-level: ScreenOffMonitor's restore target must never come from a DDC read-back — the field's corrupted -51 read clamps to brightness 0 and the "restore" turns the screen OFF; reads become advisory/diagnostic only (live bug in today's deploy, likely why screen-off only works "mostly okay"). Shipped as the write-only state machine: isDimmed flips only on CONFIRMED write sequences, ticks re-issue the failed direction, saved level used only when a read succeeded (iOS), 1.0 fallback otherwise
- [x] T1.3 - Display power endpoints: PUT /display on|off using the probe winner; wake sequence = assert user activity -> poll AV service back -> reassert luminance
- [x] T1.4 - Daemon hardening: cache max luminance at startup (validate 1...1000, re-probe on failure), retry-with-backoff when the DCP AV service drops (panel sleep does this by design now), structured logs to stdout for launchd capture
- [x] T1.5 - Kiosk install: LaunchAgent plist with KeepAlive (user session — the box is always on and unlocked, and IOPMAssertionDeclareUserActivity wants the GUI session; no LaunchDaemon/root needed) + a second KeepAlive agent relaunching RemindWall itself (no reboots means login items never re-fire; an app crash otherwise leaves the kiosk dead until someone notices) + install doc + `brew pin m1ddc` (stable v1.2.0 is the known-good; HEAD builds Apr 2025-Jun 2026 read max luminance from the wrong byte)
- [x] T1.6 - ScreenControl rework: replace M1DDCBrightness/posix_spawn with a URLSession client (request timeout, Result-based errors — kill the `?? 1.0` failure masking that breaks restore), add displayOn/displayOff alongside brightness, os.Logger for postmortems; client tests against a stubbed daemon
- [x] T1.7 - ScreenOffMonitor: off-window uses true display off on the Mac (brightness path stays for iOS), restore honors the wake ordering; in-flight guard (cancelInFlight on the work id) so a slow call can't stack ticks. Availability-consult dropped deliberately: ops THROW when the daemon's down and failed transitions self-retry next tick, so a per-tick /health round-trip adds nothing
- [x] T1.8 - Availability rework: available = /health reachable, re-checked periodically (no forever-negative cache); fix the Settings caption (still says `brew install m1ddc`)
- [x] T1.9 - Enable App Sandbox on the Mac target + companion entitlements (network.client, personal-information.photos-library, personal-information.calendars; smartcard already present — the old device.usb/disable-library-validation were libnfc-era, not needed)
- [ ] T1.10 - Container migration check: CloudKit re-sync covers the DB; verify @Shared(.appStorage) settings survive or document the one-time kiosk reconfigure
  - Happens at first sandboxed launch on Hearthstone (testing night of 2026-07-03). Expect: album/schedule/calendar/bus-window need re-picking; trackees/reminders/stops return via CloudKit; bus API key may survive (iCloud Keychain)
- [ ] T1.11 - Upload to TestFlight internal: processing passes clean (no ITMS-90296/90338), end-to-end kiosk test (scan, off-window true-off + late-reminder force-on, calendar, photos)
  - Upload + processing PASSED 2026-07-03 (both ITMS gates cleared - first sandboxed Mac build accepted). Kiosk e2e pending: reconfigure settings, bootstrap io.hotchkiss.remindwall-keepalive AFTER confirming launch, audio output = built-in speakers, watch /tmp/ddcd.log overnight (off-window true-off + late-reminder force-on)
- [x] T1.12 - CI lane for `ddcd/` — Xcode Cloud only builds the Swift side, so cargo test + clippy need their own hook (GitHub Actions or a ci_scripts addition)

## Phase R1 - Soft-disable a trackee's reminders

Why this phase: someone goes on a trip or pauses a med for a week, and today the only way to stop the dashboard nagging "Bob is late for meds" is to DELETE Bob — which throws away every reminder time and NFC-tag mapping, then you rebuild it all by hand when they're back. Add a per-trackee soft-disable that keeps the rows.

Scope decision (chotchki, 2026-07-08): disable is a per-trackee flag (`Trackee.remindersEnabled`), not per-reminder-time — "someone's reminders" = the whole person. It gates the late-alert surface ONLY: a disabled trackee never appears in `AlertLoader.lateTrackeeNames`. The tag-scan path stays UNTOUCHED — scanning a disabled trackee's tag still credits the dose and shows the green "Thank you" (the scan is the "did they do it" surface, not the "nag" surface, and recording a real tap is never wrong). Hence the name `remindersEnabled`, not `isActive` — scans are not gated, only the reminders/nagging is.

CloudKit note: `remindersEnabled` is a new column on the already-synced `trackees` table. Old CKRecords lack the field; the local `DEFAULT 1` + struct default cover the gap so a trackee synced from a pre-R1 device reads back enabled. No backfill needed.

- [x] R1.1 - Schema: add `remindersEnabled: Bool = true` to `Trackee` (init param defaulted last so every existing `Trackee(id:name:)` site still compiles) + a `"Add remindersEnabled to trackees"` migration (`ALTER TABLE "trackees" ADD COLUMN "remindersEnabled" INTEGER NOT NULL DEFAULT 1`); DaoTests cover the default
- [x] R1.2 - AlertLoader: drop late reminders whose trackee is disabled — intersect `lateTrackeeIds` with the enabled trackees before mapping to names; test proves a late-but-disabled trackee stays out of the alert
- [x] R1.3 - TrackeeDetail: a "Reminders enabled" toggle at the top of the form that writes the flag through `defaultDatabase` (mirror RemindersFeature's `withErrorReporting`+write pattern); footer states scans still work; reducer test on the write + state update
- [x] R1.4 - Trackees list: an explicit status badge per row — "Active" (green) / "Paused" (orange) capsule — so a paused trackee pops in a list of active ones without opening the detail
- [ ] R1.5 - `swift test` green (288 passing, incl. 6 new: Dao default+toggle, AlertLoader single + per-trackee filter, disabled-tag-still-scans, TrackeeDetail disable + re-enable, new-trackee-defaults-enabled) — DONE; sweep R1 to PLAN_ARCHIVE.md after in-app confirmation on the next kiosk session (toggle flips the dashboard nag off; migration lands cleanly on the live CloudKit-synced DB). TestFlight build kicked off 2026-07-08.

## Backlog
- Wake the screen during scan overlays — post-T1 this is one ScreenControl.displayOn() call from TagScanLoader feedback (iPads: restore UIScreen.brightness); pairs with N1.11's beep so scans register even mid-wake
- Harden slot subscription against a nil `slotNamed(_:)` (async `getSlot(withName:)` + rebuild on failure) — audit refuted the transient-nil trigger but the pipeline is one nil from dead-until-replug
- `associatedTag` uniqueness constraint (schema migration) — N1.9 fixes the read side only
- Sound policy for per-tap DB errors: `.error` is deliberately silent (a dead reader on the 30s backoff cycle must not buzz all night), so a DB-write failure in the dark gives no audio — the absent success ding is the only signal. Splitting infrastructure vs per-tap error cases would fix it; conscious tradeoff for now
- Test seam for the decode path: N1.4's retry-while-validCard and N1.3's muteCard pipeline branch have no unit coverage — needs a protocol abstraction over TKSmartCardSlot/TKSmartCard to fake card behavior
