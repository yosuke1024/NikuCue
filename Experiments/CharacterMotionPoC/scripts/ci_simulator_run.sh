#!/bin/bash
# Runs MotionLab scenarios on a booted iOS Simulator, recording the screen and collecting the app's diagnostics.
# Used by .github/workflows/character-motion-poc.yml; also runnable on a Mac:
#   scripts/ci_simulator_run.sh <path/to/MotionLab.app> <simulator-udid> <out-dir>
set -euo pipefail

APP="$1"
UDID="$2"
BUNDLE="placeholder.nikucue.motionlab"
mkdir -p "$3"
OUT="$(cd "$3" && pwd)"          # absolute: simctl hands --stdout/--stderr paths to the simulator's launchd

log() { echo "[$(date +%H:%M:%S)] $*"; }

container() { xcrun simctl get_app_container "$UDID" "$BUNDLE" data; }

# run_scenario <name> <seconds> <extra launch args...>; optional hook via $DURING (a function name) at $DURING_AT s
run_scenario() {
  local name="$1" seconds="$2"
  shift 2
  local video="$OUT/${name}.mp4" stdout="$OUT/${name}.stdout.log"
  log "scenario ${name}: ${seconds}s $*"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  rm -f "$(container)/Documents/"diagnostics-*.json 2>/dev/null || true
  xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$video" &
  local rec=$!
  sleep 2
  if ! xcrun simctl launch --terminate-running-process --stdout="$stdout" --stderr="$OUT/${name}.stderr.log" \
    "$UDID" "$BUNDLE" -MLScenario "$name" -MLSeconds "$seconds" "$@"; then
    log "scenario ${name}: launch with stdout capture failed; retrying without it"
    if ! xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -MLScenario "$name" -MLSeconds "$seconds" "$@"; then
      log "scenario ${name}: launch failed"
      kill -INT "$rec" 2>/dev/null || true
      wait "$rec" 2>/dev/null || true
      FAILED="${FAILED:-} ${name}"
      return 0
    fi
  fi
  local start=$SECONDS
  local hooked=0
  while (( SECONDS - start < seconds + 60 )); do
    if grep -q "ML_DIAG_DONE" "$stdout" 2>/dev/null; then break; fi
    if ls "$(container)/Documents/"diagnostics-*.json >/dev/null 2>&1; then sleep 1; break; fi
    if [[ -n "${DURING:-}" && $hooked -eq 0 && $(( SECONDS - start )) -ge ${DURING_AT:-0} ]]; then
      hooked=1
      "$DURING"
    fi
    for t in 5 30 60 85; do
      if (( SECONDS - start == t )); then xcrun simctl io "$UDID" screenshot "$OUT/${name}_t${t}s.png" >/dev/null 2>&1 || true; fi
    done
    sleep 1
  done
  sleep 1
  kill -INT "$rec" 2>/dev/null || true
  wait "$rec" 2>/dev/null || true
  cp "$(container)/Documents/"diagnostics-*.json "$OUT/" 2>/dev/null || log "no diagnostics for ${name}"
  grep -E "ML_" "$stdout" || true
}

# Background test: switch to Settings for 10 s, then bring MotionLab back (no relaunch: the running process resumes).
background_for_ten_seconds() {
  log "sending MotionLab to the background"
  xcrun simctl launch "$UDID" com.apple.Preferences >/dev/null
  sleep 10
  log "bringing MotionLab back"
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
}

xcrun simctl install "$UDID" "$APP"
xcrun simctl appinfo "$UDID" "$BUNDLE" || true
plutil -p "$APP/Info.plist" | head -40 || true
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 2>/dev/null || true

# 1. acceptance: 90 s with no input at all
run_scenario autonomous 90 -MLSeed 7
# 2. scripted taps / calls / celebrations (through the same path as the tap gesture)
run_scenario interaction 90 -MLSeed 11
# 3. background stop: 15 s in, 10 s in Settings, back for the rest
DURING=background_for_ten_seconds DURING_AT=15 run_scenario lifecycle 45 -MLSeed 5
unset DURING DURING_AT
# 4. Reduce Motion through the app setting
run_scenario reducedMotion 40 -MLSeed 3 -MLReduceMotion YES
# 5. Reduce Motion through the iOS setting (whether the Simulator applies it is recorded, not assumed)
xcrun simctl spawn "$UDID" defaults write com.apple.Accessibility ReduceMotionEnabled -bool YES || true
run_scenario systemReduceMotion 30 -MLSeed 3
xcrun simctl spawn "$UDID" defaults write com.apple.Accessibility ReduceMotionEnabled -bool NO || true
# 6. comparison renderer: SpriteKit flipbook (frames baked at launch), same engine and seed as run 1
run_scenario flipbook 60 -MLSeed 7 -MLRenderer flipbook

log "done"
ls -la "$OUT"
if [[ -n "${FAILED:-}" ]]; then log "failed scenarios:${FAILED}"; exit 1; fi
