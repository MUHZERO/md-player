// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:md_player_android/md_player_android.dart';

import 'player_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MdPlayerCache.configure(MdPlayerCacheConfiguration(
    maxBytes: 256 * 1024 * 1024,
    directoryName: 'md_player_example_cache',
  ));
  runApp(const MaterialApp(home: PlayerPage()));
}
