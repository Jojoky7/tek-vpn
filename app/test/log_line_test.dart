import 'package:flutter_test/flutter_test.dart';
import 'package:tek/src/core/engine.dart';

void main() {
  test('log lines keep the time the core wrote', () {
    final l = LogLine.fromJson({'id': 1, 'time': '12:36:35.932', 'level': 'info', 'text': 'x'});
    expect([l.time.hour, l.time.minute, l.time.second, l.time.millisecond], [12, 36, 35, 932]);
  });
}
