// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      responseDataCallback: (Map<String, dynamic>? data) async {
        // The runner extracts this stable one-line payload into each raw report.
        print('PHASE_2_1_REPORT=${jsonEncode(data ?? <String, dynamic>{})}');
        print(
            'PHASE_3_CACHE_REPORT=${jsonEncode(data ?? <String, dynamic>{})}');
      },
    );
