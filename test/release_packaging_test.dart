import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release manifest excludes debug-only Android configuration', () {
    final String manifest = File(
      'example/android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('io.flutter.embedding.android.FlutterActivity'));
    expect(manifest, isNot(contains('videoplayerexample.MainActivity')));
    expect(manifest, isNot(contains('example_lifecycle')));
    expect(manifest, isNot(contains('networkSecurityConfig')));
  });

  test('fixture cleartext policy is debug-only and loopback-scoped', () {
    final String configuration = File(
      'example/android/app/src/debug/res/xml/network_security_config.xml',
    ).readAsStringSync();

    expect(
      configuration,
      contains('<domain includeSubdomains="false">127.0.0.1</domain>'),
    );
    expect(
      configuration,
      contains('<domain includeSubdomains="false">10.0.2.2</domain>'),
    );
    expect(configuration, isNot(contains('sample-videos.com')));
    expect(configuration, isNot(contains('184.72.239.149')));
  });

  test('example release does not use debug signing', () {
    final String gradle =
        File('example/android/app/build.gradle').readAsStringSync();

    expect(gradle, isNot(contains('signingConfigs.debug')));
  });

  test('Flutter generated registrant is not tracked source', () {
    final String ignore = File('.gitignore').readAsStringSync();

    expect(
      ignore,
      contains(
        'example/android/app/src/main/java/io/flutter/plugins/'
        'GeneratedPluginRegistrant.java',
      ),
    );
  });

  test('package entrypoints do not export diagnostics or Pigeon types', () {
    for (final String path in <String>[
      'lib/md_player_android.dart',
      'lib/video_player_android.dart',
    ]) {
      final String entrypoint = File(path).readAsStringSync();
      expect(entrypoint, isNot(contains('md_player_debug.dart')));
      expect(entrypoint, isNot(contains('messages.g.dart')));
    }
  });

  test('native diagnostics registration is debuggable-gated', () {
    final String plugin = File(
      'android/src/main/java/io/flutter/plugins/videoplayer/'
      'VideoPlayerPlugin.java',
    ).readAsStringSync();

    expect(plugin, contains('ApplicationInfo.FLAG_DEBUGGABLE'));
    expect(plugin, contains('if (diagnosticsEnabled)'));
  });
}
