# Phase 3.1 bounded cache validation report

## Result

**Readiness: ready.** The API 37 preview emulator passed the 1, 3, and 10
repetition suites. The connected physical Xiaomi `24117RN76G` running Android
16/API 36 passed the complete core suite once.

| Target | Repetitions | Scenario passes | Failures | Timeouts |
| --- | ---: | ---: | ---: | ---: |
| API 37 preview emulator (Android 17) | 1 | 13 | 0 | 0 |
| API 37 preview emulator (Android 17) | 3 | 39 | 0 | 0 |
| API 37 preview emulator (Android 17) | 10 | 130 | 0 | 0 |
| Xiaomi 24117RN76G physical device (API 36) | 1 | 13 | 0 | 0 |

Raw reports and logs are retained under `build/phase_3_cache/`. The final
10-run aggregate is
`build/phase_3_cache/20260719T121710Z_7901/aggregate.json`.

## Implementation

- Added the opt-in device integration suite, Android-target runner, JSON
  aggregator, device validator, and host-side deterministic HTTP range server.
- Extended the existing range server with GET, HEAD, bounded/open ranges, 416,
  query-insensitive fixtures, per-role/per-path counters, throttling,
  availability control, restart, and deterministic shutdown.
- Reused the Phase 2.1 Flutter driver and operation diagnostics. Added
  debug-only cache generation, lease, key, cache-instance, and source ownership
  observations. They are unavailable in release builds and cannot mutate cache
  state.
- Allowed cleartext fixture traffic only to `127.0.0.1` (physical ADB reverse)
  and `10.0.2.2` (standard Android emulator host mapping) in the example app.
- Public cache APIs are unchanged from Phase 3:
  `MdPlayerCacheConfiguration`, `MdPlayerCacheStats`, and `MdPlayerCache`.
  Production cache authority and lease handoff behavior were not redesigned.

The process cache manager owns each `SimpleCache` generation. Cache-backed
sources retain a generation lease through initial playback, switching, and
rollback. Successful replacement promotes the requested lease; failed
replacement releases only the failed lease after rollback; disposal releases
the confirmed lease. Final diagnostics reported 13 cache creates, 13 releases,
zero open caches, and zero current or retired leases.

## Cache evidence

The final API 37 ten-run totals are shown below. Server counters are reset at
the audit boundary inside multi-step warm scenarios, so their upstream column
represents the operation under assertion rather than every setup request.

| Scenario | Upstream bytes | Cache-read bytes | Result |
| --- | ---: | ---: | --- |
| Disabled baseline | 10,718,160 | 0 | Both playbacks used upstream; cache stayed disabled |
| Cold cache | 4,507,450 | 851,630 | Upstream read and cache size/resource count increased |
| Warm, upstream unavailable | 0 | 6,210,710 | Full replay and first frame succeeded from cache |
| Partial cache | 5,513,204 | 3,984,204 | One playback used both cache and upstream |
| Merged audio/video warm | 0 | 5,610,117 | Distinct audio/video keys; unavailable-upstream replay passed |
| Signed-query reuse | 0 | 6,125,547 | Second URL reused one stable key |
| Quality switching | 24,127,632 | 5,731,489 | Same player/texture; cached-low return passed |
| Cached rollback | 28,707,372 | 1,467,606 | Exactly one rollback; no duplicate cache instance |
| Rapid switching | 58,845,224 | 1,209,447 | Latest operation remained authoritative |
| LRU eviction | 4,507,450 | 6,984,160 | Exact evicted key reread upstream; cache remained bounded |
| Exact video removal | 4,507,450 | 4,014,650 | `abc` removed; `abc1` and `xabc` remained warm |
| Clear | 13,522,350 | 851,630 | Active lease rejected clear; post-disposal clear and repopulation passed |
| Disable | 23,388,880 | 851,630 | Active source survived; future source uncached; bytes preserved |

The physical-device smoke produced the same 13 scenario passes. Its disabled
baseline served 1,071,816 upstream bytes, cold playback served 450,745 upstream
bytes, and the unavailable-upstream warm operation served 0 upstream bytes and
read 621,071 cached bytes.

Every final scenario ended with zero leases and zero duplicate open cache
instances. No unexpected native crash, cache lock/corruption error, or
indefinite operation occurred. Cancelled quality operations remained in raw
diagnostics and were not counted as successful switches. Ten samples are below
the configured p95 threshold, so the aggregate reports min/median/max only.

## Regression and build validation

- Phase 2.1 same-player/same-texture, first-frame ordering, command authority,
  rollback, rapid switching, surface handling, and disposal invariants are
  exercised by the cache-enabled scenarios and remained valid.
- Flutter analysis passed.
- Flutter tests passed: 55 tests.
- Android debug unit tests passed, including cache counters and generation/lease
  diagnostics.
- Fixture SHA-256 verification and runner shell syntax checks passed.
- Debug APKs were assembled and installed by every device run.
- Release assembly and final `git diff --check` passed before commit.

## Limitations

- Cache remains opt-in and Android-only.
- A fully cached progressive resource can replay without upstream, but this is
  not an offline-download guarantee. Partial entries still require upstream.
- No signed-URL retry, resolver refresh, prefetching, background download,
  adaptive HLS/DASH keying, automatic quality selection, or UI work was added.
- API 37 is a preview image; the stable physical API 36 pass is the basis for
  the final `ready` decision.

SecondBrain was queried before implementation. No relevant notes were found or
consulted, no durable external knowledge was discovered, and no SecondBrain
update is suggested.
