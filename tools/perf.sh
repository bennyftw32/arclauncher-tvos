#!/usr/bin/env bash
# Frame-timing check on the TV box: replays D-pad presses and reads present times for Arc's
# Flutter surface from SurfaceFlinger (gfxinfo can't see Flutter frames).
# Usage: tools/perf.sh <label> <KEY> [KEY...]
#   e.g. tools/perf.sh grid DPAD_RIGHT DPAD_RIGHT DPAD_DOWN
# Env: DEVICE (default 192.168.1.24:5555), PKG (default com.bennyftw32.arctv - use a profile build).
# A "janky" frame here is a gap of 1.5-6 refresh periods inside an animation; longer gaps are idle time.
set -euo pipefail
export MSYS_NO_PATHCONV=1
ADB="${ADB:-adb}"
DEVICE="${DEVICE:-192.168.1.24:5555}"
PKG="${PKG:-com.bennyftw32.arctv}"
label="$1"; shift

layer=$("$ADB" -s "$DEVICE" shell "dumpsys SurfaceFlinger --list" | tr -d '\r' \
  | grep -F "SurfaceView[$PKG/" | grep -F "(BLAST)" | head -1)
[ -n "$layer" ] || { echo "no Flutter surface for $PKG - is the app in front?"; exit 1; }

keys=""
for k in "$@"; do keys="$keys input keyevent KEYCODE_$k; sleep 0.35;"; done

"$ADB" -s "$DEVICE" shell "dumpsys SurfaceFlinger --latency-clear '$layer' >/dev/null"
"$ADB" -s "$DEVICE" shell "$keys sleep 0.5"
"$ADB" -s "$DEVICE" shell "dumpsys SurfaceFlinger --latency '$layer'" | tr -d '\r' | python -c "
import sys
lines=[l.split() for l in sys.stdin if l.strip()]
period=int(lines[0][0]); ts=[int(l[1]) for l in lines[1:] if len(l)==3 and 0<int(l[1])<9e18]
gaps=[(b-a)/1e6 for a,b in zip(ts,ts[1:])]
p=period/1e6
anim=[g for g in gaps if g<6*p]
jank=[g for g in anim if g>1.5*p]
print(f'== $label: {len(ts)} frames, refresh {p:.1f} ms')
if anim:
    s=sorted(anim); q=lambda f: s[min(len(s)-1,int(f*len(s)))]
    print(f'   frame interval p50 {q(.5):.1f} ms, p90 {q(.9):.1f} ms, p99 {q(.99):.1f} ms')
    print(f'   janky: {len(jank)}/{len(anim)} ({100*len(jank)/len(anim):.1f}%)')
"
