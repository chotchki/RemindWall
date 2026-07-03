#!/bin/bash
# T1.2 hardware probe - run ON THE KIOSK with the external monitor attached.
# Decides which mechanism ddcd's /display endpoint uses: OS display sleep
# (pmset + user-activity wake) vs DDC VCP D6 standby. Read-only except where
# it says so; every step prints what it's about to do and waits for Enter.
#
# WILL BLANK THE MONITOR during tests A and B. Total runtime ~2 minutes.

set -u
M1DDC="${M1DDC:-/opt/homebrew/bin/m1ddc}"

say()  { printf '\n=== %s\n' "$*"; }
pause(){ read -r -p "--- Press Enter to continue..." _; }

ddc_alive() { "$M1DDC" get luminance >/dev/null 2>&1; }

# Polls until DDC answers again; prints elapsed seconds. Bounded at 30s.
wait_for_ddc() {
    local start elapsed
    start=$(date +%s)
    for _ in $(seq 1 60); do
        if ddc_alive; then
            elapsed=$(( $(date +%s) - start ))
            echo "DDC answering again after ${elapsed}s"
            return 0
        fi
        sleep 0.5
    done
    echo "DDC did NOT come back within 30s"
    return 1
}

say "Baseline"
[ -x "$M1DDC" ] || { echo "m1ddc not found at $M1DDC"; exit 66; }
echo "m1ddc: $("$M1DDC" --version 2>/dev/null || echo 'version unknown')"
echo "displays:"; "$M1DDC" display list 2>&1
echo "luminance: $("$M1DDC" get luminance 2>&1) / max $("$M1DDC" max luminance 2>&1)"

say "TEST A - DDC VCP D6 standby (the pure-DDC route)"
echo "Will send 'set power 4' (standby). WATCH THE MONITOR: does it actually"
echo "power down (backlight off / power LED amber), or just blank?"
pause
"$M1DDC" set power 4; echo "sent (exit $?)"
sleep 3
echo "Probing DDC while in standby (the make-or-break question):"
if ddc_alive; then
    echo "  ACKs in standby -> DDC wake is possible on this monitor"
    A_ACK=yes
else
    echo "  NO ACK in standby -> DDC wake impossible, OS route required"
    A_ACK=no
fi
echo "Attempting DDC wake: set power 1"
"$M1DDC" set power 1; echo "sent (exit $?)"
wait_for_ddc && A_WAKE=yes || A_WAKE=no
echo "Did the monitor visibly come back on? (it may need a few seconds)"
pause

say "TEST B - OS display sleep (pmset) + user-activity wake"
echo "Will run 'pmset displaysleepnow' then wake via 'caffeinate -u -t 2'"
echo "after 8 seconds. WATCH: does the monitor enter real standby, and does"
echo "it wake on its own when the signal returns?"
pause
pmset displaysleepnow; echo "sleep sent (exit $?)"
sleep 4
echo "Probing DDC while OS-asleep (expect failure - AV service drops):"
ddc_alive && echo "  unexpectedly ACKs" || echo "  no ACK (expected)"
sleep 4
echo "Waking via caffeinate -u"
caffeinate -u -t 2
wait_for_ddc && B_WAKE=yes || B_WAKE=no

say "RESULTS"
echo "A: DDC ACK in standby:  ${A_ACK:-?}    DDC wake worked: ${A_WAKE:-?}"
echo "B: OS wake -> DDC back: ${B_WAKE:-?}"
echo
echo "Decision rule: B_WAKE=yes -> use pmset/user-activity (wake never depends"
echo "on DDC reaching a sleeping monitor). A route only if B fails and A is"
echo "yes on both. Paste this whole output into the session."
