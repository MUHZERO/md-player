<div align="center">

# md_player_android

**A Flutter video player: AndroidX Media3 on Android (separate audio and video streams, same-player quality switching, bounded caching) and AVFoundation on iOS, with modern Flutter controls on both.**
For Flutter apps that stream lessons or long videos and need more control than the stock `video_player`.

<br>

<img src="https://cdn.simpleicons.org/flutter/02569B" alt="Flutter" title="Flutter" height="36">&nbsp;&nbsp;&nbsp;
<img src="https://cdn.simpleicons.org/dart/0175C2" alt="Dart" title="Dart" height="36">&nbsp;&nbsp;&nbsp;
<img src="https://cdn.simpleicons.org/android/34A853" alt="Android" title="Android" height="36">&nbsp;&nbsp;&nbsp;
<img src="https://cdn.simpleicons.org/apple/000000" alt="iOS" title="iOS" height="36">&nbsp;&nbsp;&nbsp;
<img src="https://cdn.simpleicons.org/openjdk/437291" alt="Java" title="Java" height="36">&nbsp;&nbsp;&nbsp;
<img src="https://cdn.simpleicons.org/githubactions/2088FF" alt="GitHub Actions" title="GitHub Actions" height="36">

<br><br>

[![Validate](https://github.com/MUHZERO/md-player/actions/workflows/validate.yml/badge.svg)](https://github.com/MUHZERO/md-player/actions/workflows/validate.yml)
![Flutter](https://img.shields.io/badge/Flutter-%E2%89%A53.24-02569B?logo=flutter&logoColor=white)
![Media3](https://img.shields.io/badge/Media3-1.10.1-34A853?logo=android&logoColor=white)
![Android](https://img.shields.io/badge/Android-API%2023%2B-34A853)
![iOS](https://img.shields.io/badge/iOS-AVFoundation-000000?logo=apple)
![Tests](https://img.shields.io/badge/Dart%20tests-83-2EA44F)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

</div>

---

A Flutter video player built on AndroidX Media3 on Android and on AVFoundation
(through the endorsed `video_player_avfoundation`) on iOS. It supports direct
network media, YouTube and Vimeo resolution, separate audio and video streams
and same-player quality switching on Android, optional bounded caching on
Android, and opt-in modern Flutter controls on both platforms.

The package is derived from Flutter's `video_player_android` implementation and
continues to implement `video_player_platform_interface`. The package name is
kept for compatibility.

> **Release status:** validated for public review. The first public package
> version and Git tag have not yet been selected.

## Platform support

| Platform | Engine | Support |
| --- | --- | --- |
| Android API 23+ | Media3 (this package's Java plugin) | Full feature set |
| iOS | AVPlayer via `video_player_avfoundation` | Playback, controls, quality switching by re-opening |
| macOS, web, Windows, Linux | — | Not implemented |

| Feature | Android | iOS |
| --- | --- | --- |
| Progressive MP4, HLS | Yes | Yes |
| DASH, SmoothStreaming, RTSP | Yes | No (AVPlayer limits) |
| Separate video-only + audio-only streams | Yes (`MergingMediaSource`) | No; the resolver picks muxed streams |
| YouTube | Adaptive streams first, then muxed, then HLS | HLS muxed first, then muxed progressive |
| Quality switching | In place on the same player, first-frame confirmed | Player re-created at the current position, rollback on failure |
| `MdPlayerCache` | Yes | No (throws `UnsupportedError`) |
| Modern/legacy controls, fullscreen callbacks | Yes | Yes |

The Android plugin compiles with SDK 36, uses Java 17, and currently depends on
AndroidX Media3 1.10.1.

## Features

- Media3 playback for progressive, HLS, DASH, SmoothStreaming, and RTSP sources
- iOS playback through AVFoundation, with HLS-first source selection
- Optional merged playback of separate video-only and audio-only streams (Android)
- Race-safe controller initialization, commands, and asynchronous disposal
- Same-player manual quality switching with first-frame confirmation and rollback (Android)
- Bounded process-level Media3 cache, disabled by default (Android)
- Double-tap seeking with an accumulating side ripple and screen-reader announcement
- `controlsScale` for compact controls that keep 44 px touch targets
- Legacy controls by default and opt-in modern Flutter controls
- Host-owned fullscreen callbacks, keyboard shortcuts, volume, speed, and seeking
- YouTube and Vimeo URL resolution in the Dart layer

Automatic quality selection, captions, DRM integration, picture-in-picture,
downloads, thumbnail previews, and package-owned fullscreen/orientation policy
are not implemented.

## Installation

After the first pub.dev release, add the selected package version:

```yaml
dependencies:
  md_player_android: ^x.y.z
```

Until then, use a reviewed commit:

```yaml
dependencies:
  md_player_android:
    git:
      url: https://github.com/MUHZERO/md-player.git
      ref: COMMIT_SHA
```

On iOS, the endorsed `video_player_avfoundation` comes in as a dependency and
Flutter registers it as the only iOS implementation; `flutter build ios` runs
`pod install`. Network playback on Android
also requires the normal internet permission:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

## Basic player

Create and initialize the controller once, then await its asynchronous
disposal:

```dart
late final MdPlayerController controller;
late final Future<void> initialization;

@override
void initState() {
  super.initState();
  controller = MdPlayerController.network(
    'https://example.com/video.mp4',
    autoPlay: true,
  );
  initialization = controller.initialize();
}

@override
void dispose() {
  controller.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  return FutureBuilder<void>(
    future: initialization,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Text('Video could not be loaded');
      }
      return MdPlayer(controller: controller);
    },
  );
}
```

For code that owns shutdown sequencing, use `await controller.dispose()`.
Calling `dispose()` more than once returns the same cleanup future.

## YouTube sources

`MdPlayerController.network` uses `MdPlayerSourceResolver`, which can resolve
YouTube watch/share URLs, Vimeo URLs, and direct media URLs:

```dart
final controller = MdPlayerController.network(
  'https://www.youtube.com/watch?v=VIDEO_ID',
);
await controller.initialize();
```

High-quality YouTube formats commonly use separate video-only and audio-only
streams. On Android the controller passes both to one Media3 player through a
`MergingMediaSource`.

AVPlayer cannot merge separate streams, so on iOS the resolver never returns
them: it prefers HLS muxed streams (audio and video in one stream; AVPlayer
adapts the bitrate itself) and falls back to muxed progressive MP4. YouTube
often exposes HLS only to some clients, so many videos resolve to a single
360p muxed stream on iOS. Pass `MdPlayerSourceResolver(platform: ...)` to
test either selection.

YouTube stream URLs can expire, and availability depends on regional,
age/account, format, and other video restrictions. Applications are
responsible for ensuring their use of YouTube content and stream extraction
complies with applicable terms and permissions.

## Manual quality selection

Available streams are exposed through `controller.value.qualities`:

```dart
final quality = controller.value.qualities.first;
await controller.setQuality(quality);
```

On Android the `setQuality()` future completes when Android accepts the
request; it does not mean the replacement's first frame has rendered. On iOS
the player is re-created at the current position and the future completes
when that finishes; the previous stream is restored if the new one fails. Observe
`controller.qualitySwitchState` for terminal success or failure and
`controller.confirmedQuality` for the exact stream last confirmed by the
native player. Failed switches roll back without replacing the controller,
texture, or native player.

Automatic/adaptive quality selection is not provided.

## Modern controls

Legacy controls remain the default. Modern controls are opt-in:

```dart
MdPlayer(
  controller: controller,
  controlsMode: MdPlayerControlsMode.modern,
  controlsConfiguration: MdPlayerControlsConfiguration(
    enableVolume: true,
  ),
)
```

Modern controls follow the familiar mobile video layout: seek-back, play/pause
and seek-forward in the center, settings at the top, time and fullscreen above
a thin progress bar at the bottom edge. Settings open in a bottom sheet with
quality and playback-speed lists, optional volume and controls locking, so they
never cover the video. Double-tap the left or right third to seek by
`seekInterval`: a translucent ripple on that side shows the accumulated amount,
and every further tap on the same side while it shows (about 700 ms) seeks one
more interval. Left always seeks backward and right forward, whatever the text
direction. The amount is announced to screen readers. Keyboard actions and
accessibility labels are included. The timeline and seek controls
stay left-to-right in right-to-left locales. Modern controls do not replace the
Media3 player or own playback authority.

Locking the controls from the settings sheet ignores taps, double-taps and
drags on the video. A tap shows only an unlock button for a few seconds.

Chapters, sorted by start, are marked on the progress bar; the chapter title
appears next to the time while scrubbing. Jump to one with
`controller.seekTo(chapter.start)`:

```dart
MdPlayer(
  controller: controller,
  controlsMode: MdPlayerControlsMode.modern,
  chapters: const <MdPlayerChapter>[
    MdPlayerChapter(start: Duration.zero, title: 'Introduction'),
    MdPlayerChapter(start: Duration(minutes: 4), title: 'Exercises'),
  ],
)
```

All visible text comes from `MdPlayerControlsLabels` (English defaults), so a
localized app should pass its own labels, including `speed`, `normalSpeed`,
`quality`, `lock`, `seekBackward`, `seekForward` and `seekFeedback`.

### Configuration

| `MdPlayerControlsConfiguration` | Default | Effect |
| --- | --- | --- |
| `seekInterval` | 10 s | Step for seek buttons, arrow keys and each double-tap |
| `hideDelay` | 3 s | Delay before controls hide during playback |
| `animationDuration` | 180 ms | Fades and scales |
| `controlsScale` | 1.0 | Multiplies control icon sizes and center gaps; 0.5 to 1.5, touch targets stay ≥ 44 px |
| `enableKeyboard` | true | Keyboard shortcuts while the player has focus |
| `enableVolume` | false | Volume button, slider and shortcuts |
| `enableLock` | true | Lock action in the settings sheet |
| `speedOptions` | 0.5, 1, 1.25, 1.5, 2 | Unique positive speeds in the sheet |

`MdPlayerControlsLabels.seekFeedback` defaults to `'{seconds} seconds'`;
`{seconds}` is replaced by the accumulated amount.

## Host-owned fullscreen

The package reports fullscreen intent but never changes routes, orientation,
system UI, or activity state:

```dart
MdPlayer(
  controller: controller,
  controlsMode: MdPlayerControlsMode.modern,
  isFullscreen: isFullscreen,
  onEnterFullscreen: enterFullscreen,
  onExitFullscreen: exitFullscreen,
  onFullscreenPressed: toggleFullscreen,
)
```

The host must update `isFullscreen` and restore any orientation or system-UI
policy it changes. `onFullscreenPressed` is the compatibility fallback when a
state-specific callback is absent.

## Optional Media3 cache (Android)

Caching is Android-only and disabled by default; on other platforms every
`MdPlayerCache` call throws `UnsupportedError`. Configure it once, before creating players:

```dart
await MdPlayerCache.configure(
  MdPlayerCacheConfiguration(
    maxBytes: 256 * 1024 * 1024,
    directoryName: 'media_cache',
  ),
);
```

The cache is process-level and stored in the application's private cache
directory. Active cache-backed players hold generation leases. Configuration,
disable, clear, and targeted removal can be rejected while an affected
generation is leased; dispose the relevant controllers and retry.

```dart
final stats = await MdPlayerCache.stats();
await MdPlayerCache.removeVideo(youtubeVideoId);
await MdPlayerCache.clear();
await MdPlayerCache.disable();
```

Cache keys for resolved YouTube streams are stable across signed-query refreshes
and keep audio/video resources distinct. A partial cache entry does not
guarantee offline playback; every required byte and every required stream must
already be cached.

## Limitations

- Android and iOS are the implemented platforms; iOS has no cache, no merged
  separate streams, and switches quality by re-opening the player.
- DRM playback is not configured or validated.
- Live-stream behavior is not part of the validated feature set.
- YouTube and Vimeo extraction can break when provider responses change.
- Separate-stream playback requires compatible audio/video timelines.
- Quality changes are deliberate manual replacements, not gapless switching.
- The package does not manage fullscreen routes, orientation, or system UI.

## Troubleshooting

- Initialization failures: verify the URL, Android internet permission, codec,
  container, and provider restrictions.
- Cleartext HTTP failures: use HTTPS in production. The example permits
  loopback cleartext traffic only in its debug manifest for deterministic tests.
- Cache mutation failures: dispose cache-backed controllers before clearing,
  disabling, or replacing the active cache generation.
- Quality failures: inspect `qualitySwitchState`; a successful rollback keeps
  the previous `confirmedQuality`.

## Example

The `example/` application (Android and iOS) demonstrates legacy and modern controls, explicit
cache setup, host-owned fullscreen/orientation restoration, custom labels and
colors, and URL error handling. Paste a media URL you are authorized to play.
Committed synthetic fixtures are used only by integration tests.

## Development

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test

cd example/android
GRADLE_USER_HOME="$PWD/../../.gradle-user-home" \
  sh gradlew :md_player_android:testDebugUnitTest

cd example
flutter build ios --simulator --debug
```

Regenerate Pigeon bindings with Pigeon 27.1.1:

```bash
dart run pigeon --input pigeons/messages.dart
dart format lib/src/messages.g.dart test/test_api.g.dart
perl -pi -e 's/[ \t]+$//' \
  android/src/main/java/io/flutter/plugins/videoplayer/Messages.java
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for all checks.

## Architecture

```text
lib/                 Dart controller, widgets, source resolver, cache API
android/             Java plugin on Media3 (player, quality switching, cache)
pigeons/messages.dart  typed Dart ↔ Java channel definitions
example/             showcase app and integration tests
test/                Dart unit and widget tests
```

---

<div align="center">

Designed and built by [MuhDroid](https://muhdroid.com).

BSD 3-Clause. See [LICENSE](LICENSE). This repository contains code derived
from Flutter's Android video player implementation; existing attribution and
copyright headers are preserved.

</div>
