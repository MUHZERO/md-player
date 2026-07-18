#!/bin/sh
set -eu

device=
repetitions=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --device) device=${2-}; shift 2 ;;
    --repetitions) repetitions=${2-}; shift 2 ;;
    *) echo "Usage: $0 --device <id> --repetitions <count>" >&2; exit 64 ;;
  esac
done

[ -n "$device" ] && [ -n "$repetitions" ] || {
  echo "Usage: $0 --device <id> --repetitions <count>" >&2
  exit 64
}
case "$repetitions" in *[!0-9]*|'') echo "repetitions must be a positive integer" >&2; exit 64;; esac
[ "$repetitions" -gt 0 ] || { echo "repetitions must be positive" >&2; exit 64; }

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fixtures="$root/example/assets/phase_2_1"
for file in audio.m4a low.mp4 high.mp4 muxed.mp4 invalid.mp4 SHA256SUMS FFMPEG_VERSION; do
  [ -s "$fixtures/$file" ] || {
    echo "Blocked: missing generated fixture $fixtures/$file" >&2
    echo "Run tool/generate_phase_2_1_fixtures.sh with an existing ffmpeg." >&2
    exit 2
  }
done

reports="$root/build/phase_2_1"
mkdir -p "$reports"
i=1
while [ "$i" -le "$repetitions" ]; do
  log="$reports/run_$i.log"
  (cd "$root/example" && flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/phase_2_1_test.dart \
    --device-id="$device" \
    --dart-define=PHASE_2_1_FIXTURES=true) 2>&1 | tee "$log"
  payload=$(sed -n 's/^PHASE_2_1_REPORT=//p' "$log" | tail -1)
  [ -n "$payload" ] || { echo "Run $i produced no JSON report" >&2; exit 1; }
  printf '%s\n' "$payload" > "$reports/run_$i.json"
  i=$((i + 1))
done

dart "$root/tool/aggregate_phase_2_1.dart" "$reports" "$repetitions"
echo "Completed $repetitions repetition(s); reports: $reports"
