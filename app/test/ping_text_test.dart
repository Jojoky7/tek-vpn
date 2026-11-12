import 'package:flutter_test/flutter_test.dart';
import 'package:tek/src/services/storage.dart';
import 'package:tek/src/ui/widgets.dart';

void main() {
  test('no number until the real check passes', () {
    // The provider answers the TCP handshake itself under a whitelist.
    expect(pingText(const CheckResult(tcpMs: 2)), '');
    expect(pingText(const CheckResult(alive: false, tcpMs: 2)), '—');
  });

  test('a working server shows the time of the real request', () {
    expect(pingText(const CheckResult(alive: true, tcpMs: 40, realMs: 180)), contains('180'));
    expect(pingText(const CheckResult(alive: true, tcpMs: 40)), contains('40'));
  });
}
