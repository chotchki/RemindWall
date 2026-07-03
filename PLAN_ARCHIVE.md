# PLAN_ARCHIVE.md

## Phase N1 - NFC Scan Reliability (completed 2026-07-03)

Problem: intermittent "tapped the tag, nothing happened." An audit found the scan pipeline failed SILENTLY at every layer — marginal taps filtered out before becoming events (`.muteCard` / probing→empty died at the `.validCard`-only filter), brief taps losing the decode race (tag leaves the RF field mid-session, TKSmartCard.h documents every session op fails after removal), every degraded result mapped to `.none` (the `.error` overlay existed but was UNREACHABLE), zombie continuations eating events after settings round-trips, and DB write errors thrown into the void.

- [x] N1.1 - Add a distinct "tag detected but unreadable" ReaderState case (decode failures map to it; `.noTag` stays the silent cancellation sentinel)
- [x] N1.2 - Render unreadable + error results in TagScanLoader ("tap again and hold the tag" overlay; `.error` becomes reachable)
- [x] N1.3 - Watch `.muteCard` in the SlotMonitor filter and deliver unreadable without attempting decode
- [x] N1.4 - Retry decodeCard (bounded) while slot.state is still `.validCard` before reporting unreadable
- [x] N1.5 - Cancellation handling in nextValidCard: withTaskCancellationHandler + wire up the dead cancelWaiter so cancelled effects deregister
- [x] N1.6 - Buffer semantics: a trailing decode failure must not overwrite a buffered `.tagPresent`
- [x] N1.7 - Cancel the dashboard scan loop on onDisappear (stops false lastScan writes while associating tags in settings)
- [x] N1.8 - Catch DB errors in the `._tagScanned` effect and surface them as `.error`
- [x] N1.9 - Duplicate-tag scans: prefer a currently-scannable reminder among matches over `first(where:)`'s arbitrary pick
- [x] N1.10 - Tests: TestStore coverage for every new TagScanLoader path, SmartCardMonitor cancellation + buffer tests, `swift test` clean
- [x] N1.11 - Audible scan feedback: distinct success/failure sounds on `_scanProcessed` — the reader's own beep only proves detection, an app sound proves end-to-end processing, and it works when the panel is dark. Kiosk note: default audio output must be the Mac's built-in speakers (HDMI/monitor audio dies when the panel sleeps)
- [x] N1.12 - Adversarial-review fixes (12 confirmed findings, 0 refuted): buffer TTL (2s) so a settings-window tap can't replay as a live scan on dashboard return; cancellation-aware deliver() (synchronous cancelled-id set — real events never resume into dead effects, cancelled callers can't consume the buffer); AVAudioSession .playback so iPad silent mode can't mute feedback; trailing RF-bounce failure can't stomp a showing success overlay; stopMonitoring also cancels in-flight DB processing; overlapping windows credit the not-yet-scanned reminder (lastScan-aware pick); regression tests for each

Notable: the review pass caught N1.7 + the event buffer INTERACTING to resurrect the exact false-med-credit bug N1.7 was built to kill (a tap buffered during a settings visit replayed as live on dashboard return) — closed by the buffer TTL. Also new: a 30s backoff on `.readerError` in the scan loop so a dead reader shows a persistent error instead of hot-spinning, and `.error` results are deliberately SILENT (no sound) so that backoff cycle can't buzz all night.

Exit evidence: `swift test` 276/276; app-scheme run (unit + Catalyst UI tests) 260/260, 0 failed; Catalyst app build clean. Deferred to Backlog with tradeoffs stated: per-tap DB error sound policy, decode-path test seam.
