import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tek/src/model/server.dart';
import 'package:tek/src/parse/links.dart';
import 'package:tek/src/xray/config_builder.dart';

const stand =
    'vless://1b4e3a2c-5d6f-4a8b-9c0d-1e2f3a4b5c6d@127.0.0.1:2083?security=reality&sni=vk.com&fp=firefox&pbk=-vOyZ_nEJ7fEFBDEFIwBXMqJ1bydkjLl6toqR9ulugs&sid=abcd1234&spx=%2F&type=xhttp&path=%2Fapi%2Fv1%2Fdata&mode=auto#🇳🇱 Нидерланды';
const dead =
    'vless://1b4e3a2c-5d6f-4a8b-9c0d-1e2f3a4b5c6d@127.0.0.1:2999?security=reality&sni=vk.com&fp=firefox&pbk=-vOyZ_nEJ7fEFBDEFIwBXMqJ1bydkjLl6toqR9ulugs&sid=abcd1234&type=xhttp&path=%2Fapi%2Fv1%2Fdata#🇸🇪 Швеция';
const named =
    'trojan://secret@uk.example.com:443?sni=uk.example.com&type=ws&path=%2Fws&fragment=tlshello,50-100,5#🇬🇧 Великобритания';

List<ServerNode> servers() =>
    [parseShareLink(stand), parseShareLink(dead), parseShareLink(named)];

Map<String, dynamic> outboundByTag(Map<String, dynamic> c, String tag) =>
    (c['outbounds'] as List).cast<Map<String, dynamic>>().firstWhere(
        (o) => o['tag'] == tag);

void main() {
  test('TUN config: every server, DNS hijack, Russian sites direct', () {
    final list = servers();
    final b = XrayConfigBuilder(list);
    final c = b.connection(list.first, const ConnectOptions(mode: TunnelMode.tun),
        api: const ApiProxy(10820, 'u', 'p'));
    final tags = [for (final o in c['outbounds'] as List) o['tag']];
    expect(tags, containsAll(['proxy', 'srv-0', 'srv-1', 'srv-2', 'fragment',
        'fragment-1', 'direct', 'block', 'dns-out']));
    expect(tags.first, 'proxy');

    final proxy = outboundByTag(c, 'proxy');
    expect(proxy['streamSettings']['sockopt']['dialerProxy'], 'fragment');
    final uk = outboundByTag(c, 'srv-2');
    expect(uk['streamSettings']['sockopt']['dialerProxy'], 'fragment-1');
    expect(outboundByTag(c, 'fragment-1')['settings']['fragment']['length'], '50-100');

    final rules = (c['routing']['rules'] as List).cast<Map<String, dynamic>>();
    expect(rules.first['inboundTag'], ['api-in']);
    expect(rules.any((r) => r['port'] == '53' && r['outboundTag'] == 'dns-out'), isTrue);
    expect(rules.any((r) => (r['domain'] as List?)?.contains('geosite:category-ru') == true), isTrue);
    expect(rules.last['outboundTag'], 'proxy');

    final dns = c['dns'] as Map;
    final direct = (dns['servers'] as List).first as Map;
    expect(direct['address'], '77.88.8.8');
    expect(direct['domains'], contains('full:uk.example.com'));
  });

  test('without Russian direct and fragmentation', () {
    final list = servers();
    final c = XrayConfigBuilder(list).connection(list.first,
        const ConnectOptions(mode: TunnelMode.proxy, ruDirect: false, fragmentation: false));
    final rules = (c['routing']['rules'] as List).cast<Map<String, dynamic>>();
    expect(rules.any((r) => r.containsKey('domain')), isFalse);
    final tags = [for (final o in c['outbounds'] as List) o['tag']];
    expect(tags, isNot(contains('fragment')));
    // The server with a name resolves it through Xray's DNS.
    expect(outboundByTag(c, 'srv-2')['streamSettings']['sockopt']['domainStrategy'], 'UseIPv4');
  });

  test('apps that go around the VPN, and sites by hand', () {
    final list = servers();
    final b = XrayConfigBuilder(list);
    const opts = ConnectOptions(
      mode: TunnelMode.tun,
      appsMode: 'except',
      apps: ['Telegram', '/Applications/Safari.app/'],
      directDomains: ['domain:mybank.com'],
      proxyDomains: ['domain:kinopoisk.ru'],
    );
    final c = b.connection(list.first, opts);
    final rules = (c['routing']['rules'] as List).cast<Map<String, dynamic>>();
    int at(bool Function(Map<String, dynamic>) f) => rules.indexWhere(f);
    final apps = at((r) => r['process'] != null);
    final vpn = at((r) => (r['domain'] as List?)?.contains('domain:kinopoisk.ru') == true);
    final mine = at((r) => (r['domain'] as List?)?.contains('domain:mybank.com') == true);
    final ru = at((r) => (r['domain'] as List?)?.contains('geosite:category-ru') == true);
    expect(rules[apps]['outboundTag'], 'direct');
    expect(rules[apps]['process'], ['Telegram', '/Applications/Safari.app/']);
    // DNS goes first, then the apps; a site sent through the VPN wins over
    // the Russian list.
    expect(at((r) => r['port'] == '53'), lessThan(apps));
    expect(apps, lessThan(vpn));
    expect(rules[vpn]['outboundTag'], 'proxy');
    expect(vpn, lessThan(mine));
    expect(rules[mine]['outboundTag'], 'direct');
    expect(mine, lessThan(ru));
    // Tek's own site is on a Russian IP and still goes through the VPN.
    final own = at((r) => (r['domain'] as List?)?.contains('domain:tekvpn.com') == true);
    expect(rules[own]['outboundTag'], 'proxy');
    expect(own, lessThan(ru));
    expect(own, lessThan(at((r) => (r['ip'] as List?)?.contains('geoip:ru') == true)));
    expect(rules.last['outboundTag'], 'proxy');
    expect(rules.last.containsKey('process'), isFalse);

    final dns = (c['dns']['servers'] as List).cast<Map<String, dynamic>>();
    expect(dns.first['tag'], 'dns-proxy');
    expect(dns.first['domains'], ['domain:kinopoisk.ru']);
    expect(dns[1]['address'], '77.88.8.8');
    expect(dns[1]['domains'], containsAll(['domain:mybank.com', 'geosite:category-ru']));
  });

  test('only some apps use the VPN', () {
    final list = servers();
    final c = XrayConfigBuilder(list).connection(
        list.first,
        const ConnectOptions(
            mode: TunnelMode.proxy,
            appsMode: 'only',
            apps: ['chrome'],
            proxyDomains: ['domain:ozon.ru']));
    final rules = (c['routing']['rules'] as List).cast<Map<String, dynamic>>();
    final last = rules[rules.length - 1], proxy = rules[rules.length - 2];
    expect(proxy, {'network': 'tcp,udp', 'outboundTag': 'proxy', 'process': ['chrome']});
    expect(last, {'network': 'tcp,udp', 'outboundTag': 'direct'});
    final quic = rules.firstWhere((r) => r['port'] == '443');
    expect(quic['process'], ['chrome']);
    final vpn = rules.firstWhere((r) => (r['domain'] as List?)?.contains('domain:ozon.ru') == true);
    expect(vpn['process'], ['chrome']);
  });

  test('no apps chosen means every app uses the VPN', () {
    final list = servers();
    final c = XrayConfigBuilder(list).connection(
        list.first, const ConnectOptions(mode: TunnelMode.tun, appsMode: 'only'));
    final rules = (c['routing']['rules'] as List).cast<Map<String, dynamic>>();
    expect(rules.any((r) => r.containsKey('process')), isFalse);
    expect(rules.last['outboundTag'], 'proxy');
  });

  test('writes configs for the core to check', () async {
    final out = Platform.environment['TEK_CONFIG_OUT'];
    if (out == null) return;
    final list = servers();
    final b = XrayConfigBuilder(list);
    const enc = JsonEncoder.withIndent('  ');
    final files = {
      'tun.json': b.connection(list.first, const ConnectOptions(mode: TunnelMode.tun),
          api: const ApiProxy(10820, 'tek', 'secret')),
      'proxy.json': b.connection(
          list.first,
          const ConnectOptions(mode: TunnelMode.proxy, socksPort: 10818, httpPort: 10819),
          api: const ApiProxy(10820, 'tek', 'secret')),
      'probe.json': b.probe(const ConnectOptions(mode: TunnelMode.proxy)),
      'apps-except.json': b.connection(
          list.first,
          const ConnectOptions(
              mode: TunnelMode.tun,
              appsMode: 'except',
              apps: ['Telegram', '/Applications/Telegram.app/'],
              directDomains: ['domain:mybank.com'],
              proxyDomains: ['domain:kinopoisk.ru', 'full:www.ozon.ru'])),
      'apps-only.json': b.connection(
          list.first,
          const ConnectOptions(
              mode: TunnelMode.proxy,
              appsMode: 'only',
              apps: ['chrome'],
              proxyDomains: ['domain:kinopoisk.ru'])),
    };
    for (final e in files.entries) {
      await File('$out/${e.key}').writeAsString(enc.convert(e.value));
    }
  });
}
