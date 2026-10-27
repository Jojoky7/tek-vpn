import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tek/src/model/server.dart';
import 'package:tek/src/parse/links.dart';
import 'package:tek/src/parse/subscription_parser.dart';

const nl =
    'vless://1b4e3a2c-5d6f-4a8b-9c0d-1e2f3a4b5c6d@82.115.7.56:2083?encryption=none&security=reality&sni=vk.com&fp=firefox&pbk=-vOyZ_nEJ7fEFBDEFIwBXMqJ1bydkjLl6toqR9ulugs&sid=abcd1234&spx=%2F&type=xhttp&path=%2Fapi%2Fv1%2Fdata&mode=auto#%F0%9F%87%B3%F0%9F%87%B1%20%D0%9D%D0%B8%D0%B4%D0%B5%D1%80%D0%BB%D0%B0%D0%BD%D0%B4%D1%8B';
const se =
    'vless://1b4e3a2c-5d6f-4a8b-9c0d-1e2f3a4b5c6d@62.182.193.32:2083?security=reality&sni=vk.com&fp=firefox&pbk=-vOyZ_nEJ7fEFBDEFIwBXMqJ1bydkjLl6toqR9ulugs&sid=abcd1234&type=xhttp&path=/api/v1/data&mode=auto#🇸🇪 Швеция';

void main() {
  group('share links', () {
    test('TekVPN VLESS + XHTTP + REALITY', () {
      final s = parseShareLink(nl);
      expect(s.name, 'Нидерланды');
      expect(s.countryCode, 'nl');
      expect(s.host, '82.115.7.56');
      expect(s.port, 2083);
      final stream = s.outbound['streamSettings'] as Map;
      expect(stream['network'], 'xhttp');
      expect(stream['security'], 'reality');
      final reality = stream['realitySettings'] as Map;
      expect(reality['serverName'], 'vk.com');
      expect(reality['fingerprint'], 'firefox');
      expect(reality['shortId'], 'abcd1234');
      expect(reality['spiderX'], '/');
      final xhttp = stream['xhttpSettings'] as Map;
      expect(xhttp['path'], '/api/v1/data');
      expect(xhttp['mode'], 'auto');
      final user =
          ((s.outbound['settings'] as Map)['vnext'] as List).first['users'][0];
      expect(user['encryption'], 'none');
    });

    test('raw emoji names and the fragment parameter', () {
      final s = parseShareLink(
          se.replaceFirst('#', '&fragment=tlshello,100-200,1#'));
      expect(s.countryCode, 'se');
      expect(s.name, 'Швеция');
      expect(s.fragment, FragmentSettings.tested);
    });

    test('ids are stable and differ between servers', () {
      expect(parseShareLink(nl).id, parseShareLink(nl).id);
      expect(parseShareLink(nl).id, isNot(parseShareLink(se).id));
    });

    test('trojan, shadowsocks and vmess', () {
      final t = parseShareLink(
          'trojan://secret@example.com:443?sni=example.com&type=ws&path=%2Fws#DE');
      expect(t.protocol, 'trojan');
      expect((t.outbound['streamSettings'] as Map)['security'], 'tls');

      final ss = parseShareLink(
          'ss://${base64Url.encode(utf8.encode('chacha20-ietf-poly1305:pass'))}@1.2.3.4:8388#Finland');
      expect(ss.protocol, 'shadowsocks');
      expect(ss.countryCode, 'fi');
      final server = ((ss.outbound['settings'] as Map)['servers'] as List).first;
      expect(server['method'], 'chacha20-ietf-poly1305');
      expect(server['password'], 'pass');

      final vm = parseShareLink('vmess://${base64.encode(utf8.encode(jsonEncode({
            'v': '2',
            'ps': 'Латвия',
            'add': 'lv.example.com',
            'port': '443',
            'id': '1b4e3a2c-5d6f-4a8b-9c0d-1e2f3a4b5c6d',
            'net': 'ws',
            'path': '/v',
            'tls': 'tls',
          })))}');
      expect(vm.protocol, 'vmess');
      expect(vm.countryCode, 'lv');
    });

    test('unsupported links are refused', () {
      expect(() => parseShareLink('hysteria2://x@1.2.3.4:443'),
          throwsA(isA<LinkException>()));
      expect(
          () => parseShareLink(
              'vless://id@1.2.3.4:443?security=reality&sni=vk.com'),
          throwsA(isA<LinkException>()));
    });
  });

  group('subscriptions', () {
    test('base64 body with headers', () {
      final body = base64.encode(utf8.encode('$nl\n$se\n'));
      final p = parseSubscription(body, headers: {
        'subscription-userinfo':
            'upload=1000; download=2000; total=10737418240; expire=1798761600',
        'profile-title': 'base64:${base64.encode(utf8.encode('TekVPN'))}',
        'profile-update-interval': '12',
      });
      expect(p.servers.length, 2);
      expect(p.info.title, 'TekVPN');
      expect(p.info.used, 3000);
      expect(p.info.total, 10737418240);
      expect(p.info.expire!.toUtc().year, 2027);
      expect(p.info.updateIntervalHours, 12);
    });

    test('plain body with #key lines, duplicates and junk', () {
      final body = '#profile-title: Tek\n'
          '#subscription-userinfo: upload=0; download=0; total=0; expire=0\n'
          '$nl\n$nl\nhysteria2://x@1.2.3.4:443#bad\n\n';
      final p = parseSubscription(body);
      expect(p.servers.length, 1);
      expect(p.skipped.length, 1);
      expect(p.info.title, 'Tek');
      expect(p.info.unlimited, isTrue);
      expect(p.info.expire, isNull);
    });

    test('Happ fragmentation headers', () {
      final p = parseSubscription(nl, headers: {
        'fragmentation-enable': '1',
        'fragmentation-length': '50-100',
      });
      expect(p.info.fragment!.length, '50-100');
      expect(p.info.fragment!.packets, 'tlshello');
    });

    test('JSON configs keep their fragment chain as settings', () {
      final config = {
        'remarks': '🇱🇻 Латвия',
        'outbounds': [
          {
            'tag': 'proxy',
            'protocol': 'vless',
            'settings': {
              'vnext': [
                {
                  'address': '5.6.7.8',
                  'port': 2083,
                  'users': [
                    {'id': '1b4e3a2c-5d6f-4a8b-9c0d-1e2f3a4b5c6d', 'encryption': 'none'}
                  ]
                }
              ]
            },
            'streamSettings': {
              'network': 'xhttp',
              'security': 'reality',
              'realitySettings': {'serverName': 'vk.com', 'publicKey': 'k'},
              'sockopt': {'dialerProxy': 'fragment'},
            },
          },
          {
            'tag': 'fragment',
            'protocol': 'freedom',
            'settings': {
              'fragment': {'packets': 'tlshello', 'length': '100-200', 'interval': '1'}
            },
          },
          {'tag': 'direct', 'protocol': 'freedom'},
        ],
      };
      final p = parseSubscription(jsonEncode([config]));
      final s = p.servers.single;
      expect(s.countryCode, 'lv');
      expect(s.fragment, FragmentSettings.tested);
      expect(s.hasOwnDialer, isFalse);
      expect(s.outbound.containsKey('tag'), isFalse);
      expect((s.outbound['streamSettings'] as Map).containsKey('sockopt'), isFalse);
    });

    test('an HTML page is not a subscription', () {
      expect(() => parseSubscription('<!DOCTYPE html><html></html>'),
          throwsA(isA<SubscriptionFormatException>()));
      expect(() => parseSubscription('   '),
          throwsA(isA<SubscriptionFormatException>()));
    });
  });
}
