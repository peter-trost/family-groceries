import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The iOS client ID lives in two files: the Dart define and the reversed
/// URL scheme Google redirects back to. A mismatch only fails on a device.
void main() {
  test('Auth.xcconfig carries the reversed iOS client ID', () {
    final defines = jsonDecode(
      File('config/auth.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final iosClientId = defines['GOOGLE_IOS_CLIENT_ID']! as String;
    final xcconfig = File('ios/Flutter/Auth.xcconfig').readAsStringSync();
    final reversed = RegExp(
      r'^GOOGLE_REVERSED_CLIENT_ID\s*=\s*(\S*)\s*$',
      multiLine: true,
    ).firstMatch(xcconfig)![1];

    expect(reversed, iosClientId.split('.').reversed.join('.'));
  });
}
