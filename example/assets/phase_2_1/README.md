# Phase 2.1 integration fixtures

Run `tool/generate_phase_2_1_fixtures.sh` from the repository root. The script
uses only an already-installed `ffmpeg`, requires its `libx264` encoder, and
never downloads or installs anything.

The deterministic inputs are a 10-second 440 Hz AAC tone and 30 fps `testsrc2`
video. Outputs are `audio.m4a`, H.264 video-only `low.mp4` (320×180) and
`high.mp4` (640×360), H.264/AAC `muxed.mp4`, and `invalid.mp4`. The invalid file
retains the fast-start MP4 container metadata and a deliberately truncated
`mdat` payload. `SHA256SUMS` and `FFMPEG_VERSION` record exact provenance.

Generated binaries are intentionally absent until the script succeeds. This
private directory is registered only for integration assets; the public demo
does not reference its contents.
