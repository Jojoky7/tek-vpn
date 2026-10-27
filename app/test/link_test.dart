import 'package:flutter_test/flutter_test.dart';
import 'package:tek/src/services/subscription_service.dart';

void main() {
  group('links that add a subscription', () {
    const sub = 'https://tekvpn.com/sub/abc123';

    test('the subscription link itself', () {
      expect(SubscriptionService.normalizeUrl(sub), sub);
      expect(SubscriptionService.normalizeUrl('  $sub\n'), sub);
    });

    test('tek:// and happ:// links from the site', () {
      expect(SubscriptionService.normalizeUrl('tek://add/$sub'), sub);
      expect(SubscriptionService.normalizeUrl('TEK://import/$sub'), sub);
      expect(SubscriptionService.normalizeUrl('happ://add/$sub'), sub);
      expect(SubscriptionService.normalizeUrl('tek://subscribe?url=${Uri.encodeComponent(sub)}'), sub);
    });

    test('an encoded or folded link inside the tek:// link', () {
      expect(SubscriptionService.normalizeUrl('tek://add/${Uri.encodeComponent(sub)}'), sub);
      expect(SubscriptionService.normalizeUrl('tek://add/https:/tekvpn.com/sub/abc123'), sub);
    });

    test('a bare domain gets https', () {
      expect(SubscriptionService.normalizeUrl('tekvpn.com/sub/abc123'), sub);
    });

    test('not a subscription', () {
      expect(SubscriptionService.normalizeUrl(''), isNull);
      expect(SubscriptionService.normalizeUrl('hello world'), isNull);
      expect(SubscriptionService.normalizeUrl('vless://uuid@host:443'), isNull);
    });
  });
}
