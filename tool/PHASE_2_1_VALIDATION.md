# Phase 2.1 controlled-device validation

Generate fixtures with `tool/generate_phase_2_1_fixtures.sh`, then run:

```sh
tool/run_phase_2_1.sh --device <id> --repetitions 1   # smoke
tool/run_phase_2_1.sh --device <id> --repetitions 3   # preflight
tool/run_phase_2_1.sh --device <id> --repetitions 10  # final emulator report
```

The runner uses the existing integration driver JSON response channel and
writes raw operation-correlated reports under `build/phase_2_1/`. Each report
contains failures, timeouts, restoration data, rollback and surface timing,
stale-frame/replacement counters, and min/median/max operation duration. It
adds nearest-rank p95 only at 20 or more samples.

The lifecycle scenarios remove and restore the Flutter texture widget, rotate
the Activity, and background/foreground the real task. Explicit Activity
recreation is a separate manual command on the private debug channel because a
host that destroys its Flutter engine also disposes the player and test
isolate; record that as host-engine disposal, not a same-player failure.

Automated runs do not capture audio. Report observed gaps only as
“non-playing intervals”; the periodic tone is a manual validation aid.

Passing only the installed API 37 preview AVD makes caching status
`provisionally ready`. Use `ready` only after the core suite also passes on a
stable Android emulator or physical device.
