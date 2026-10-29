import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tek/src/core/elevate.dart';

void main() {
  test('the helper plist starts tek-core as a daemon for the user', () {
    final plist = MacHelper.plistFor(501);
    expect(plist, contains('<string>daemon</string>'));
    expect(plist, contains('<string>501</string>'));
    expect(plist, contains('<string>/Library/Application Support/Tek</string>'));
    final out = Platform.environment['PLIST_OUT'];
    if (out != null) File(out).writeAsStringSync(plist);
  });
}
