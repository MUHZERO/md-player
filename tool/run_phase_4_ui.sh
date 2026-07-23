#!/bin/sh
set -eu

usage() { echo "Usage: $0 --device <device-id> [--repetitions <count>]" >&2; exit 64; }
device=
repetitions=1
while [ "$#" -gt 0 ]; do
  case "$1" in
    --device) [ "$#" -ge 2 ] || usage; device=$2; shift 2 ;;
    --repetitions) [ "$#" -ge 2 ] || usage; repetitions=$2; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$device" ] || usage
case "$repetitions" in *[!0-9]*|'') usage;; esac
[ "$repetitions" -gt 0 ] || usage

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fixtures="$root/example/assets/phase_2_1"
for file in audio.m4a low.mp4 high.mp4 muxed.mp4 invalid.mp4 SHA256SUMS FFMPEG_VERSION; do
  [ -s "$fixtures/$file" ] || { echo "Missing fixture: $fixtures/$file" >&2; exit 2; }
done
(cd "$fixtures" && shasum -a 256 -c SHA256SUMS) >/dev/null

devices_file=$(mktemp)
flutter devices --machine > "$devices_file"
kind=$(dart "$root/tool/phase_3_device.dart" "$device" < "$devices_file")
rm -f "$devices_file"

run_id=$(date -u +%Y%m%dT%H%M%SZ)_$$
reports="$root/build/phase_4_ui/$run_id"
mkdir -p "$reports"
server_log="$reports/server.log"
dart "$root/tool/phase_3_http_server.dart" "$fixtures" > "$server_log" 2>&1 &
server_pid=$!
reverse_port=
adb=${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb
cleanup() {
  if [ -n "$reverse_port" ]; then "$adb" -s "$device" reverse --remove "tcp:$reverse_port" >/dev/null 2>&1 || true; fi
  kill "$server_pid" >/dev/null 2>&1 || true
  wait "$server_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

tries=0
while ! grep -q '^PHASE_3_SERVER=' "$server_log"; do
  kill -0 "$server_pid" 2>/dev/null || { cat "$server_log" >&2; exit 2; }
  tries=$((tries + 1))
  [ "$tries" -lt 100 ] || { echo "Range server startup timed out" >&2; exit 2; }
  sleep 0.1
done
port=$(sed -n 's/^PHASE_3_SERVER={"port":\([0-9][0-9]*\)}$/\1/p' "$server_log" | tail -1)
[ -n "$port" ] || { echo "Could not parse range server port" >&2; exit 2; }

if [ "$kind" = emulator ]; then
  origin="http://10.0.2.2:$port"
else
  [ -x "$adb" ] || adb=$(command -v adb || true)
  [ -n "$adb" ] || { echo "adb is required" >&2; exit 2; }
  reverse_port=$("$adb" -s "$device" reverse tcp:0 "tcp:$port")
  origin="http://127.0.0.1:$reverse_port"
fi

i=1
while [ "$i" -le "$repetitions" ]; do
  log="$reports/run_$i.log"
  echo "Phase 4 UI run $i/$repetitions on $device"
  if (cd "$root/example" && perl -e '$SIG{ALRM}=sub{exit 124}; alarm shift; exec @ARGV' 600 \
    flutter drive \
      --driver=test_driver/integration_test.dart \
      --target=integration_test/phase_4_ui_test.dart \
      --device-id="$device" \
      --dart-define="PHASE_4_ORIGIN=$origin" \
      --dart-define="PHASE_4_RUN_ID=$run_id" \
      --dart-define="PHASE_4_REPETITION=$i") > "$log" 2>&1; then :; else
    status=$?; cat "$log"; echo "Run $i failed or timed out (status $status)" >&2; exit 1
  fi
  payload=$(sed -n 's/^PHASE_4_UI_REPORT=//p' "$log" | tail -1)
  [ -n "$payload" ] || { cat "$log"; echo "Run $i produced no JSON report" >&2; exit 1; }
  printf '%s\n' "$payload" > "$reports/run_$i.json"
  i=$((i + 1))
done

dart "$root/tool/aggregate_phase_4_ui.dart" "$reports" "$repetitions"
echo "Passed $repetitions repetition(s); aggregate: $reports/aggregate.json"
