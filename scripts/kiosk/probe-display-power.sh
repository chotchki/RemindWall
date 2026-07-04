#!/bin/bash
# T1.2 hardware probe v2 - run ON THE KIOSK with the external monitor attached.
# Decides which mechanism ddcd's /display endpoint uses.
#
# v2 fixes over v1 (which produced a misleading RESULTS block):
#  - Test A is SKIPPED (not falsely passed) when m1ddc lacks `set power`
#    (brew 1.2.0 does - it's a HEAD-only feature)
#  - read-stability check: 5 luminance reads, because this LG has returned
#    corrupted values (-51 / max 62) in the field
#  - refuses to run while RemindWall is up (its 30s DDC polls interleave with
#    the probe's transactions and corrupt both)
#  - timestamped DDC timeline through the sleep transition instead of one
#    4s-later probe
#  - your eyeball observations are prompted and CAPTURED in the output
#
# WILL BLANK THE MONITOR during test B. Total runtime ~3 minutes.

set -u
M1DDC="${M1DDC:-/opt/homebrew/bin/m1ddc}"

say()  { printf '\n=== %s\n' "$*"; }
pause(){ read -r -p "--- Press Enter to continue..." _; }
ask()  {
    # ask <var> <question> - records a y/n observation into the transcript
    local var=$1; shift
    local answer
    read -r -p "OBSERVATION: $* [y/n] " answer
    printf 'RECORDED: %s = %s\n' "$var" "$answer"
    eval "$var=\$answer"
}

ddc_alive() { "$M1DDC" get luminance >/dev/null 2>&1; }

# Prints a "t=<sec> ddc=<ok|dead> value=<n>" line each second for $1 seconds.
ddc_timeline() {
    local secs=$1 t v
    for t in $(seq 0 "$secs"); do
        if v=$("$M1DDC" get luminance 2>/dev/null); then
            echo "  t=${t}s ddc=ok value=${v}"
        else
            echo "  t=${t}s ddc=dead"
        fi
        sleep 1
    done
}

say "Preflight"
[ -x "$M1DDC" ] || { echo "m1ddc not found at $M1DDC"; exit 66; }
if pgrep -x RemindWall >/dev/null 2>&1; then
    echo "RemindWall is RUNNING - its DDC polls will corrupt this probe."
    echo "Quit it first, then re-run. (pgrep -x RemindWall to verify)"
    exit 65
fi
echo "RemindWall: not running (good)"
echo "session: SSH=${SSH_CONNECTION:+yes}${SSH_CONNECTION:-no}"
echo "displays:"; "$M1DDC" display list 2>&1

say "Read stability - 5 luminance reads (watch for corruption)"
for i in $(seq 1 5); do
    echo "  read $i: current=$("$M1DDC" get luminance 2>&1) max=$("$M1DDC" max luminance 2>&1)"
done
echo "Sane = current 0-100ish, max ~100, CONSISTENT across reads."
echo "Negative or wildly varying values = corrupted DDC reads on this panel."

say "TEST A - DDC VCP D6 standby (pure-DDC route)"
if "$M1DDC" set power 4 >/dev/null 2>&1; then
    echo "set power accepted. WATCH: did the monitor power down (LED amber)?"
    sleep 3
    if ddc_alive; then A_ACK=yes; else A_ACK=no; fi
    echo "DDC ACK in standby: $A_ACK"
    "$M1DDC" set power 1 >/dev/null 2>&1 && A_WAKE_SENT=yes || A_WAKE_SENT=no
    echo "wake command accepted: $A_WAKE_SENT"
    sleep 3
    ask A_VISIBLE_OFF "did the monitor VISIBLY power down during test A?"
    ask A_VISIBLE_ON  "did it come back on after the wake command?"
else
    echo "SKIPPED: this m1ddc build has no 'set power' (brew 1.2.0 doesn't;"
    echo "it's a HEAD-only feature). Route A unavailable as installed."
    A_ACK=skipped; A_VISIBLE_OFF=skipped; A_VISIBLE_ON=skipped
fi

say "TEST B - OS display sleep (pmset) + user-activity wake"
echo "Sequence: displaysleepnow -> 15s DDC timeline -> caffeinate wake ->"
echo "10s DDC timeline. WATCH the monitor the whole time."
pause
pmset displaysleepnow; echo "sleep sent (exit $?)"
echo "DDC timeline during sleep transition:"
ddc_timeline 15
echo "Waking via caffeinate -u"
caffeinate -u -t 2
echo "DDC timeline after wake:"
ddc_timeline 10
ask B_VISIBLE_OFF "did the panel VISIBLY go dark / into standby (LED change)?"
ask B_VISIBLE_ON  "did it VISIBLY wake after caffeinate?"

say "RESULTS (paste this whole transcript back)"
echo "A: ack-in-standby=$A_ACK visible-off=$A_VISIBLE_OFF visible-on=$A_VISIBLE_ON"
echo "B: visible-off=${B_VISIBLE_OFF:-?} visible-on=${B_VISIBLE_ON:-?}"
echo "Decision rule: B visible-off+on = use pmset/user-activity. The DDC"
echo "timeline tells us how long ddcd must wait after wake before touching"
echo "luminance."
