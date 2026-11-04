import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tek/src/services/desktop_apps.dart';
import 'package:tek/src/services/settings.dart';
import 'package:tek/src/xray/ru_sites.dart';

void main() {
  test('a typed site becomes a domain rule', () {
    expect(siteRule('example.com'), 'domain:example.com');
    expect(siteRule('  https://www.Example.com/page?x=1 '), 'domain:example.com');
    expect(siteRule('http://user@shop.example.ru:8080/'), 'domain:shop.example.ru');
    expect(siteRule('*.funpay.com'), 'domain:funpay.com');
    expect(siteRule('www.ru'), 'domain:www.ru');
    expect(siteRule('пример.рф'), 'domain:xn--e1afmkfd.xn--p1ai');
    expect(siteRule('госуслуги.рф'), 'domain:xn--c1aapkosapc.xn--p1ai');
    expect(siteRule('рф'), 'domain:xn--p1ai');
    expect(siteRule(''), isNull);
    expect(siteRule('not a site'), isNull);
    expect(siteRule('-bad-.com'), isNull);
  });

  test('rules read back as sites', () {
    expect(siteLabel('domain:example.com'), 'example.com');
    expect(siteLabel('domain:ru'), '.ru');
    expect(siteLabel('domain:xn--p1ai'), '.рф');
    expect(siteLabel('full:www.ozon.ru'), 'full:www.ozon.ru');
  });

  test('the Russian list is read out of geosite.dat', () {
    final rules = geositeRules(File('assets/geo/geosite.dat').readAsBytesSync(), 'category-ru');
    expect(rules.length, greaterThan(500));
    expect(rules, containsAll(['domain:ru', 'domain:su', 'domain:xn--p1ai', 'domain:vk.com']));
    expect(rules.every((r) => r.contains(':')), isTrue);
    expect(geositeRules(File('assets/geo/geosite.dat').readAsBytesSync(), 'no-such'), isEmpty);
  });

  test('every popular service has its own id and domains', () {
    final ids = {for (final r in ruServices) r.id};
    expect(ids.length, ruServices.length);
    for (final r in ruServices) {
      expect(r.domains, isNotEmpty);
      for (final d in r.domains) {
        expect(siteRule(d), 'domain:$d');
      }
    }
  });

  test('apps typed by hand', () {
    expect(appRule('Telegram.exe', mac: false), 'Telegram.exe');
    expect(appRule('discord', mac: false), 'discord.exe');
    expect(appRule(r'"C:\Program Files\Foo\foo.EXE"', mac: false), 'foo.EXE');
    expect(appRule('a|b', mac: false), isNull);
    expect(appRule('/Applications/Telegram.app', mac: true), '/Applications/Telegram.app/');
    expect(appRule('/usr/local/bin/curl', mac: true), '/usr/local/bin/curl');
    expect(appLabel('/Applications/Telegram.app/'), 'Telegram');
    expect(appLabel('Telegram.exe'), 'Telegram.exe');
    expect(windowsAppRules(['discord.exe']), containsAll(['discord', 'Discord', 'DISCORD']));
    expect(windowsAppRules(['Telegram.exe']), contains('Telegram'));
  });

  test('settings keep the new lists', () {
    const st = Settings(
      ruServicesOff: ['kinopoisk'],
      directSites: ['domain:mybank.com'],
      vpnSites: ['domain:ozon.ru'],
      developer: true,
    );
    final back = Settings.fromJson(st.toJson());
    expect(back.ruServicesOff, ['kinopoisk']);
    expect(back.directSites, ['domain:mybank.com']);
    expect(back.vpnSites, ['domain:ozon.ru']);
    expect(back.developer, isTrue);
    final old = Settings.fromJson({'ruDirect': false});
    expect(old.ruDirect, isFalse);
    expect(old.vpnSites, isEmpty);
    expect(old.developer, isFalse);
  });
}
