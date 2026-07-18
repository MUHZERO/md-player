# Phase 2.1 validation report — 2026-07-18

## Outcome

Host-testable infrastructure is implemented. Production playback behavior and
the public package API remain unchanged. Controlled device measurement is
blocked before execution because `ffmpeg` is not installed and fixture
downloads/installations are prohibited.

## Completed checks

- `dart format .`: pass
- `flutter analyze`: pass
- `flutter test`: 46 tests pass
- `example/android/gradlew :md_player_android:testDebugUnitTest`: pass
- `example/android/gradlew :app:assembleDebug`: pass
- Debug merged manifest selects the example-only lifecycle harness
- Fixture and runner shell syntax/gating: pass

## Environment and blocked stages

- `ffmpeg`: unavailable; no fixture binaries or provenance hashes generated
- Android AVD: `Resizable_Experimental` is installed but was not started,
  because the fixture precondition cannot pass
- Physical/stable Android device: none connected
- 1/3/10 repetition runs: not executed
- Raw device operation reports: not produced
- Caching readiness: not evaluated (neither `provisionally ready` nor `ready`)

The next executable step is to install nothing automatically: once `ffmpeg`
already exists, run `tool/generate_phase_2_1_fixtures.sh`, then run the smoke,
preflight, and final commands in `tool/PHASE_2_1_VALIDATION.md` against the
installed AVD. API 37 preview results can establish only `provisionally ready`;
a stable emulator or physical-device core-suite pass is required for `ready`.
