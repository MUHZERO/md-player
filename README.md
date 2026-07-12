# MD Player

Android video player fork for Flutter with optional synced separate video and
audio stream playback.

This package is based on Flutter's `video_player_android` implementation and
keeps normal `video_player` platform behavior working. The fork adds a direct
Android API for apps that already resolve separate media URLs, such as a
video-only stream plus an audio-only stream.

## Features

- Android implementation for Flutter `video_player`
- Optional synced video/audio playback with ExoPlayer `MergingMediaSource`
- Video quality switching while keeping the existing audio stream
- Example app that resolves YouTube streams outside the native plugin
- Pigeon-generated platform messages kept from source

## Usage

For normal `video_player` playback, use the platform interface as usual.

For separate video/audio URLs:

```dart
import 'package:md_player_android/md_player_android.dart';

final int? textureId = await MdPlayerAndroid().createWithAudio(
  videoUri: videoOnlyUrl,
  audioUri: audioOnlyUrl,
);
```

To switch video quality for the same texture:

```dart
await MdPlayerAndroid().changeQuality(textureId, newVideoOnlyUrl);
```

## YouTube

YouTube extraction is intentionally handled outside the Android plugin. Resolve
streams in Dart or your app layer, then pass the final video-only and audio-only
URLs to `MdPlayerAndroid`.

## Development

```bash
flutter pub get
dart run pigeon --input pigeons/messages.dart
flutter analyze
flutter test
```

Android unit tests can be run through the example Gradle wrapper:

```bash
cd example/android
sh gradlew :md_player_android:testDebugUnitTest
```

## License

BSD-style license. See [LICENSE](LICENSE).
