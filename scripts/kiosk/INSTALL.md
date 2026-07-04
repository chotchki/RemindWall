# Kiosk setup (Hearthstone)

One-time install of the pieces the sandboxed TestFlight build can't carry
itself: the ddcd brightness daemon and the launchd agents that keep everything
alive on a box that never reboots. Everything runs as YOUR user in the GUI
session — no sudo, no LaunchDaemons.

## 1. Pin m1ddc

```sh
brew install m1ddc   # if not already present
brew pin m1ddc       # v1.2.0 is the known-good; HEAD builds Apr 2025-Jun 2026
                     # read max luminance from the wrong byte offset
```

The pin matters on an unattended box: a background `brew upgrade` swapping the
binary mid-flight is a silent way to corrupt every brightness operation.

## 2. Build + install ddcd

```sh
cd ddcd
cargo build --release
cp target/release/ddcd /usr/local/bin/ddcd
```

Defaults: port 8377, m1ddc at `/opt/homebrew/bin/m1ddc`, 5s per-call timeout.
Override with `DDCD_PORT` / `DDCD_M1DDC` / `DDCD_TIMEOUT_MS` in the plist's
`EnvironmentVariables` if they ever need to change (8377 collides with nothing
currently on the box, check `lsof -iTCP -sTCP:LISTEN` if adding services).

## 3. Load the launch agents

```sh
cp scripts/kiosk/io.hotchkiss.ddcd.plist ~/Library/LaunchAgents/
cp scripts/kiosk/io.hotchkiss.remindwall-keepalive.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/io.hotchkiss.ddcd.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/io.hotchkiss.remindwall-keepalive.plist
```

The remindwall-keepalive agent exists because this box never reboots — login
items never re-fire, so without it an app crash leaves the kiosk dead until
someone walks past. CAVEAT it also makes the TestFlight 90-day expiry a real
deadline: an expired build refuses to LAUNCH, so a crash past day 90 becomes a
60s relaunch-refuse loop. Ship a build before then. Remove the keepalive agent
before intentionally quitting the app for maintenance:

```sh
launchctl bootout gui/$(id -u)/io.hotchkiss.remindwall-keepalive
```

## 4. Verify

```sh
curl -s -H 'x-ddcd: 1' http://127.0.0.1:8377/health
# {"status":"ok","m1ddc_present":true}
curl -s -H 'x-ddcd: 1' http://127.0.0.1:8377/brightness
# NOTE: this monitor's DDC READS are garbage (probe 2026-07-03) so expect a
# 502 "implausible" here - that is CORRECT behavior. Writes are what work:
curl -s -X PUT -H 'x-ddcd: 1' -H 'Content-Type: application/json' \
  -d '{"brightness":1.0}' http://127.0.0.1:8377/brightness -w '%{http_code}\n'
# 204
tail -f /tmp/ddcd.log
```

## 5. Audio route

System Settings -> Sound -> Output: select the Mac's BUILT-IN speakers, not
the monitor. HDMI/monitor audio dies when the panel sleeps, and the scan
feedback sounds (success ding / failure buzz) are the only confirmation that
works with the panel dark.
