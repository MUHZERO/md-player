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
(cd "$fixtures" && shasum -a 256 -c SHA256SUMS) >/dev/null

devices_file=$(mktemp)
trap 'rm -f "$devices_file"' EXIT INT TERM
flutter devices --machine > "$devices_file"
dart "$root/tool/phase_3_device.dart" "$device" < "$devices_file" >/dev/null
rm -f "$devices_file"
trap - EXIT INT TERM

run_id=$(date -u +%Y%m%dT%H%M%SZ)_$$
reports="$root/build/phase_2_1/$run_id"
mkdir -p "$reports"
i=1
while [ "$i" -le "$repetitions" ]; do
  log="$reports/run_$i.log"
  if (cd "$root/example" && perl -e '$SIG{ALRM}=sub{exit 124}; alarm shift; exec @ARGV' 600 \
    flutter drive \
      --driver=test_driver/integration_test.dart \
      --target=integration_test/phase_2_1_test.dart \
      --device-id="$device" \
      --dart-define=PHASE_2_1_FIXTURES=true) > "$log" 2>&1; then
    cat "$log"
  else
    status=$?
    cat "$log"
    echo "Run $i failed or timed out (status $status)" >&2
    exit 1
  fi
  payload=$(sed -n 's/^PHASE_2_1_REPORT=//p' "$log" | tail -1)
  [ -n "$payload" ] || { echo "Run $i produced no JSON report" >&2; exit 1; }
  printf '%s\n' "$payload" > "$reports/run_$i.json"
  i=$((i + 1))
done

dart "$root/tool/aggregate_phase_2_1.dart" "$reports" "$repetitions"
echo "Completed $repetitions repetition(s); reports: $reports"
