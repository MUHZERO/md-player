# Phase 4 — Opt-in Modern Player UI

## Result

Phase 4 adds an opt-in Flutter controls layer without changing Media3, Pigeon,
source replacement, rollback, leases, lifecycle, or cache implementation. The
legacy controls remain the constructor and behavior default.

## Public API

- `MdPlayerControlsMode { legacy, modern }`
- `MdPlayerStyle` with host-theme accent fallback and foreground, scrim, focus,
  progress-background, and buffered colors
- `MdPlayerControlsConfiguration` with animation, hide, seek, keyboard, volume,
  lock, and validated speed options
- `MdPlayerControlsLabels` and `MdPlayerControlsIcons` defaults and overrides
- Additive `MdPlayer` title, subtitle, close, top-action, fullscreen-state,
  retry, loading-builder, and error-builder arguments
- `MdPlayerValue.volume`, race-safe `setVolume`, and mute restoration
- Exact read-only `MdPlayerController.confirmedQuality`

`onEnterFullscreen`/`onExitFullscreen` take precedence for their matching host
state; `onFullscreenPressed` remains the fallback. The package does not change
routes, orientation, system UI, or Activity state.

## Compatibility and architecture

One internal adapter owns the controller listener and the existing quality
listener. Equality-checked notifiers project player identity, aspect ratio,
playback, timeline, buffering, resolving, errors, speed/volume, exact confirmed
quality, and quality-switch state.

The platform texture is a stable `RepaintBoundary` child that listens only to
player identity. Both legacy and modern overlays sit above that child. Legacy
appearance and interactions remain intact while position polling now rebuilds
only the legacy overlay.

Modern controls keep visibility, settings, drag preview, lock, and gesture
feedback local. Playback, progress, buffering, and quality overlays use their
targeted projections. Debug-only rebuild counters live in the intentionally
unexported `md_player_debug.dart`; release snapshots are empty because all
counter mutations are assertion-gated.

## Behavior

- Visibility states: hidden, visible, interacting, settings, locked, and error;
  cancellable generation-checked hide timers
- Physical-third double tap: backward, play/pause, forward; repeated seeks
  accumulate and clamp
- 48 dp progress target with buffered/played tracks, thumb, tap/drag preview,
  and one final seek
- Replay inferred at known-duration completion
- Inline settings with stable resolution/itag sorting and duplicate-label
  disambiguation; failed rollback keeps settings open
- Compact `<480 px` or `<280 px`, expanded `>=900 px` and `>=420 px`, otherwise
  standard
- Scoped `Shortcuts`, `Actions`, and `Focus`: Space/K, arrows/J/L, optional M
  and volume arrows, F, and Escape; no autofocus or interception outside player
- `SafeArea`, text scaling, theme colors, accessible-navigation timer behavior,
  and disabled-animation duration handling
- Separate resolving, buffering, quality-switching, fatal error, and retry UI;
  native error details are not displayed by default

No Auto quality, captions, PiP, thumbnails, downloads, prefetching, looping, or
cache-state UI was added.

## Rebuild measurement

The widget test resets debug counters, builds one legacy player, changes only
the polled position projection, and records:

| Counter | Builds |
| --- | ---: |
| Surface | 1 |

The same `Texture` widget instance remains mounted after the update. The Phase
4 integration report includes all five Flutter counters alongside native
texture/player diagnostics.

## Example and device target

The example retains legacy mode and adds a modern opt-in toggle, compact
preview, custom amber accent and labels, volume controls, retry handling,
explicit 256 MiB cache configuration, and host-owned fullscreen. It restores
its declared portrait orientation policy after fullscreen and disposal.

`example/integration_test/phase_4_ui_test.dart` and
`tool/run_phase_4_ui.sh` reuse Phase 3 fixtures, checksums, range server,
device classification, emulator host mapping, physical-device ADB reverse,
timeouts, native diagnostics, JSON records, and aggregation. The target covers
playback, progress drag, quality, speed, fullscreen callback flow, lifecycle,
widget removal, cache statistics, and stable texture/player identity.

## Verification

### Environment and cache

- macOS 26.5.1; Flutter 3.44.5 stable; Dart 3.12.2
- Android SDK: `/Users/muhdroid/Library/Android/sdk`, SDK 36.1/build-tools 36.1
- Java: Android Studio JBR 21.0.10
- Device: `Resizable_Experimental`, `sdk_gphone16k_arm64`, Android 17/API 37,
  16 KiB preview image
- Physical API 36 device: not connected
- Exact prior permission gate: the managed sandbox denied writes to Flutter's
  `/opt/homebrew/share/flutter/bin/cache`, Gradle's wrapper lock under
  `~/.gradle`, Gradle's local lock socket, and ADB's local smart socket. The
  underlying files remained owned by the user.
- Workaround: `GRADLE_USER_HOME="$PWD/.gradle-user-home"` from the repository
  root (or `"$PWD/../../.gradle-user-home"` from `example/android`) plus
  `GRADLE_RO_DEP_CACHE="$HOME/.gradle/caches"`. `.gradle-user-home/` is ignored.
  No SDK permissions, global caches, or SDK components were changed.
- The debug assembly requires network metadata once because Flutter's
  `integration_test` plugin declares dynamic AndroidX versions. Subsequent
  artifacts remain in the repository-local cache.

### Automated gates

| Gate | Result |
| --- | --- |
| `dart format .` | pass, 34 files unchanged |
| `flutter analyze` | pass, no issues |
| Flutter tests | pass, 63/63 |
| Android `:md_player_android:testDebugUnitTest` | pass, 53/53; 0 failures/skips |
| `:app:assembleDebug` | pass |
| `:app:assembleRelease` | pass |
| Debug APK | 192,610,812 bytes |
| Release APK | 55,690,986 bytes |
| Fixture SHA-256 checks | pass, five media fixtures |
| Phase 2.1/3/4 shell syntax | pass |
| `git diff --check` | pass |

The release manifest uses `FlutterActivity`, not the debug lifecycle
`MainActivity`, and is not debuggable. The debug diagnostics method channel is
guarded by `ApplicationInfo.FLAG_DEBUGGABLE`, so it is not registered in the
release application. No lifecycle harness, raw Phase 4 report, or screenshot
path is present in the release package. The example's pre-existing
deterministic Phase 2.1 assets remain packaged; Phase 4 added no report or
screenshot assets.

### Phase 2.1 quality regression

One Android repetition passed with no recorded failure or timeout. Seven
authoritative operations covered completed and rapidly cancelled switches,
first-frame-before-completion ordering, and one failed switch with exactly one
successful rollback. Texture/player authority was retained and no callback was
published after disposal.

### Phase 3 cache regression

One repetition passed all 13 scenarios with zero failures and zero timeouts:
cold and warm reads, unavailable-upstream warm playback, partial cache, distinct
merged audio/video keys, signed-query reuse, cached quality switching and
rollback, rapid switching, LRU removal, exact removal, clear/disable lease
behavior. Every scenario recorded `duplicateCacheInstanceCount=0` and ended
with zero active generation leases.

### Phase 4 device runs

| Run | Result | Aggregate |
| --- | --- | --- |
| Smoke | 1/1 pass | `build/phase_4_ui/20260722T194917Z_38824/aggregate.json` |
| Preflight | 3/3 pass | `build/phase_4_ui/20260722T195054Z_39231/aggregate.json` |
| Final | 10/10 pass | `build/phase_4_ui/20260722T195436Z_39959/aggregate.json` |

There were no scenario failures or timeouts. Each final repetition recorded one
player creation/disposal, texture ID `0` within that fresh application process,
one stable native player identity per run, successful play and drag seek,
authoritative `1080p` completion, preserved `1.5x` speed, one enter and one exit
fullscreen callback, lifecycle pause/resume, widget removal, one cache manager,
three distinct cache keys, and zero final leases. Different player identity
values between fresh repetitions are expected process/session creation, not
same-session replacement.

Final per-run rebuild counts were identical:

| Counter | Builds |
| --- | ---: |
| Surface | 1 |
| Controls shell | 6 |
| Progress | 6 |
| Buffering overlay | 7 |
| Quality overlay | 7 |

Thus position/drag, settings, quality, host fullscreen-state rebuild, lifecycle,
and controls visibility changed targeted UI while the video surface remained at
one build. Native diagnostics recorded one player and one source replacement
for the successful quality switch, without replacing the player or texture.

### Manual review

Ignored screenshots were captured under `build/phase_4_ui/manual_review/`.
The valid compact visible and hidden frames show the decoded fixture surface,
amber progress styling, readable title/time labels, consistent icons and scrim,
adequate bottom-action spacing, and no RenderFlex overflow or clipped critical
action. The focused 400x240 widget regression also covers the compact settings
overflow found during validation.

The headless API 37 preview AVD became extremely slow during accessibility-
driven capture of the remaining settings, submenu, drag, feedback, indicator,
error, locked, fullscreen, and large-text states. Those screenshots were not
accepted as evidence, and this report makes no subjective visual-quality claim
for those uncaptured states. Their structure, semantics, layout, focus,
gestures, errors, and timers remain covered by Flutter tests and the Android
integration run, but automation is not a substitute for the missing visual
inspection.

### Confirmed defects fixed

1. Compact settings were added below the flexible playback area and overflowed
   at 400x240. Settings now reuse that flexible area; a focused widget test
   verifies speed and quality remain reachable without overflow.
2. The stable Flutter surface widget rebuilt when the host updated fullscreen
   state. The state now retains the surface subtree until the controller
   changes; a focused test and all 14 successful post-fix device repetitions
   record `surface=1`.
3. The Phase 4 device harness assumed expanded inline speed/quality controls and
   visible fullscreen controls. It now follows compact settings and restores
   controls before host fullscreen actions.
4. Android release XML validation required explicit `includeSubdomains` values
   for loopback fixture domains. A focused packaging test covers both entries.

No Media3, Pigeon, cache authority, source replacement, rollback, lease, or
public API change was made during Phase 4.1.

### Readiness

**Provisionally ready.** All automated build, regression, and API 37 preview
device gates passed, including the final ten repetitions. A stable Android
emulator or physical device did not participate, and the complete requested
manual screenshot matrix remains outstanding.

## SecondBrain

- Queried: yes
- Note consulted: `Projects/MD Player.md`
- Durable knowledge used: controller → platform/Pigeon → Media3 → Flutter
  texture flow; native quality replacement retains the player/texture
- Suggested update: none. Phase 4 is fully represented by repository source and
  this report, and no SecondBrain edit was authorized.

## Next phase

Run one core smoke and complete the visual screenshot matrix on a stable Android
emulator or the physical API 36 device when available. Promote from
`provisionally ready` to `ready` only after that pass.
