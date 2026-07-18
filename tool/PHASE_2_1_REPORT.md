# Phase 2.1 validation report — 2026-07-18

## Outcome

Phase 2.1 passes on the installed `Resizable_Experimental` arm64 Android 17 /
API 37 preview AVD. Caching status is **provisionally ready**; a stable Android
emulator or physical-device core-suite pass is still required for `ready`.

Device validation exposed and fixed one native ordering race: Media3 can emit
the accepted first frame before `STATE_READY`. The switch now remembers that
frame and completes only after READY instead of rolling back on a false timeout.
The public package API is unchanged.

## Completed checks

- `dart format .`: pass
- `flutter analyze`: pass
- `flutter test`: 46 tests pass
- `example/android/gradlew :md_player_android:testDebugUnitTest`: pass
- `example/android/gradlew :app:assembleDebug`: pass
- Debug merged manifest selects the example-only lifecycle harness
- Fixture and runner shell syntax/gating: pass
- Fixture regeneration produced identical SHA-256 hashes: pass
- API 37 smoke (1 repetition): pass
- API 37 preflight (3 repetitions): pass
- API 37 final (10 repetitions): pass
- Separate API 37 `Activity.recreate()` check: the old engine released its
  ExoPlayer, and the restarted isolate passed with zero active players

## Final API 37 measurements

- 10/10 runs passed with no scenario failure or timeout
- 70 operations: 30 completed, 30 cancelled, 10 failed as intentionally invalid
- 10/10 invalid replacements rolled back successfully; no other rollback
- Rejected stale frames: 0
- Maximum restoration delta: 10 ms
- Request → acceptance: min 0.821 ms, median 1.927 ms, max 6.802 ms,
  nearest-rank p95 5.145 ms
- Acceptance → READY: min 55.587 ms, median 115.766 ms, max 257.577 ms,
  nearest-rank p95 239.705 ms
- First frame → completion: min 1.195 ms, median 15.854 ms, max 32.713 ms,
  nearest-rank p95 30.495 ms
- Request → terminal state: min 4.106 ms, median 77.287 ms, max 260.655 ms,
  nearest-rank p95 241.608 ms
- Rollback: min 150.535 ms, median 168.135 ms, max 190.586 ms; no p95
  because only 10 rollback samples exist
- Accepted first frames preceded READY by 1.033–32.491 ms, confirming the race
  covered by the new native unit test
- Automated audio capture: none; no observed non-playing interval is claimed

Raw per-run JSON and logs plus the 70-record aggregate are in
`build/phase_2_1/`.

## Remaining limitation

Widget removal, rotation, and background/foreground retained player and texture
identity, but this API 37 texture implementation did not emit a native surface
loss callback (`surfaceLossCount` remained 0). Explicit Activity recreation
destroyed the Flutter engine and disposed the player, as expected. It remains a
separate host-level observation: `flutter drive` stays connected to the
destroyed engine even though the restarted isolate completes, so that check
does not publish through the main runner's JSON channel. Repeat the core suite
on a stable emulator or physical device before promoting caching status to
`ready`.
