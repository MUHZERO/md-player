import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release manifest excludes the debug lifecycle activity', () {
    final String manifest = File(
      'example/android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('io.flutter.embedding.android.FlutterActivity'));
    expect(manifest, isNot(contains('videoplayerexample.MainActivity')));
    expect(manifest, isNot(contains('example_lifecycle')));
  });

  test('fixture network domains explicitly reject subdomains', () {
    final String configuration = File(
      'example/android/app/src/main/res/xml/network_security_config.xml',
    ).readAsStringSync();

    expect(
      configuration,
      contains('<domain includeSubdomains="false">127.0.0.1</domain>'),
    );
    expect(
      configuration,
      contains('<domain includeSubdomains="false">10.0.2.2</domain>'),
    );
  });
}
