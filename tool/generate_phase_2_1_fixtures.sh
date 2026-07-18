#!/bin/sh
set -eu

command -v ffmpeg >/dev/null 2>&1 || {
  echo "ffmpeg is required but will not be installed or downloaded." >&2
  exit 1
}
ffmpeg -hide_banner -encoders 2>/dev/null | grep -q 'libx264' || {
  echo "The installed ffmpeg does not provide libx264." >&2
  exit 1
}

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
out="$root/example/assets/phase_2_1"
mkdir -p "$out"
common='-hide_banner -loglevel error -y'

# A periodic tone makes interruptions recognizable during manual validation.
# shellcheck disable=SC2086
ffmpeg $common -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=10' \
  -map_metadata -1 -threads 1 -c:a aac -b:a 96k -movflags +faststart "$out/audio.m4a"

for size in 320x180 640x360; do
  name=low
  [ "$size" = 640x360 ] && name=high
  # shellcheck disable=SC2086
  ffmpeg $common -f lavfi -i "testsrc2=size=$size:rate=30:duration=10" \
    -map_metadata -1 -threads 1 -an -c:v libx264 -preset medium -profile:v main -level 3.0 \
    -pix_fmt yuv420p -g 60 -keyint_min 60 -sc_threshold 0 \
    -movflags +faststart "$out/$name.mp4"
done

# shellcheck disable=SC2086
ffmpeg $common -i "$out/low.mp4" -i "$out/audio.m4a" -c copy \
  -map_metadata -1 -threads 1 -movflags +faststart -shortest "$out/muxed.mp4"

# Keep the fast-start ftyp/moov metadata and only the first bytes of mdat.
perl -0777 -e '$d=<>; $i=index($d,"mdat"); die "mdat not found\n" if $i<0; print substr($d,0,$i+132)' \
  "$out/muxed.mp4" > "$out/invalid.mp4"

(cd "$out" && shasum -a 256 audio.m4a low.mp4 high.mp4 muxed.mp4 invalid.mp4 > SHA256SUMS)
ffmpeg -version | sed -n '1p' > "$out/FFMPEG_VERSION"
echo "Generated fixtures in $out"
