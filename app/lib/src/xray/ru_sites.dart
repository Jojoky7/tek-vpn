import 'dart:convert';
import 'dart:typed_data';

/// A popular Russian service in the list of sites that go around the VPN.
class RuService {
  const RuService(this.id, this.ru, this.en, this.domains);
  final String id;
  final String ru;
  final String en;

  /// Domains with all their subdomains.
  final List<String> domains;

  List<String> get rules => [for (final d in domains) 'domain:$d'];
}

/// Services people look for first. All of .ru, .su and .рф goes around the
/// VPN anyway; the list also names each service's other domains (vk.com,
/// yastatic.net) and lets one of them go through the VPN on its own.
const ruServices = <RuService>[
  RuService('gosuslugi', 'Госуслуги', 'Gosuslugi', ['gosuslugi.ru']),
  RuService('nalog', 'Налоговая и «Мой налог»', 'Tax service', ['nalog.ru', 'nalog.gov.ru']),
  RuService('mos', 'Mos.ru', 'Mos.ru', ['mos.ru']),
  RuService('sber', 'Сбер', 'Sber', ['sberbank.ru', 'sber.ru', 'sberbank.com']),
  RuService('tbank', 'Т-Банк', 'T-Bank', ['tbank.ru', 'tinkoff.ru', 'tbank-online.com']),
  RuService('vtb', 'ВТБ', 'VTB', ['vtb.ru', 'vtb.com']),
  RuService('alfa', 'Альфа-Банк', 'Alfa-Bank', ['alfabank.ru', 'alfabank.st']),
  RuService('gpb', 'Газпромбанк', 'Gazprombank', ['gazprombank.ru', 'gazprombank.com']),
  RuService('yandex', 'Яндекс', 'Yandex',
      ['yandex.ru', 'ya.ru', 'yandex.net', 'yandex.com', 'yastatic.net']),
  RuService('vk', 'ВКонтакте', 'VK', ['vk.com', 'vk.ru', 'vk.me', 'userapi.com', 'vkuser.net']),
  RuService('mail', 'Mail.ru', 'Mail.ru', ['mail.ru', 'imgsmail.ru']),
  RuService('ok', 'Одноклассники', 'Odnoklassniki', ['ok.ru', 'mycdn.me']),
  RuService('dzen', 'Дзен', 'Dzen', ['dzen.ru']),
  RuService('ozon', 'Ozon', 'Ozon', ['ozon.ru', 'ozon.com', 'ozone.ru']),
  RuService('wb', 'Wildberries', 'Wildberries',
      ['wildberries.ru', 'wb.ru', 'wbbasket.ru', 'wbstatic.net']),
  RuService('avito', 'Авито', 'Avito', ['avito.ru', 'avito.st']),
  RuService('kinopoisk', 'Кинопоиск', 'Kinopoisk', ['kinopoisk.ru']),
  RuService('rutube', 'Rutube', 'Rutube', ['rutube.ru']),
  RuService('okko', 'Okko', 'Okko', ['okko.tv']),
  RuService('ivi', 'Иви', 'ivi', ['ivi.ru']),
  RuService('pochta', 'Почта России', 'Russian Post', ['pochta.ru']),
  RuService('rzd', 'РЖД', 'Russian Railways', ['rzd.ru']),
  RuService('2gis', '2ГИС', '2GIS', ['2gis.ru', '2gis.com']),
  RuService('hh', 'hh.ru', 'hh.ru', ['hh.ru']),
  RuService('mts', 'МТС', 'MTS', ['mts.ru']),
  RuService('megafon', 'МегаФон', 'MegaFon', ['megafon.ru']),
  RuService('beeline', 'Билайн', 'Beeline', ['beeline.ru']),
  RuService('t2', 'Т2', 'T2', ['t2.ru', 'tele2.ru']),
  RuService('funpay', 'FunPay', 'FunPay', ['funpay.com']),
  RuService('kaspersky', 'Kaspersky', 'Kaspersky', ['kaspersky.ru', 'kaspersky.com']),
];

/// A site the person typed ("https://www.Example.com/page") as an Xray
/// domain rule ("domain:example.com"); null when it is not a site name.
String? siteRule(String input) {
  var s = input.trim().toLowerCase();
  if (s.isEmpty) return null;
  s = s.replaceFirst(RegExp(r'^[a-z][a-z0-9+.-]*://'), '');
  s = s.split(RegExp(r'[/?#]')).first;
  s = s.replaceFirst(RegExp(r'^[^@]*@'), '');
  s = s.replaceFirst(RegExp(r':\d+$'), '');
  if (s.startsWith('*.')) s = s.substring(2);
  if (s.startsWith('.')) s = s.substring(1);
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  if (s.startsWith('www.') && s.split('.').length > 2) s = s.substring(4);
  final labels = s.split('.');
  for (var i = 0; i < labels.length; i++) {
    final l = labels[i];
    if (l.isEmpty || l.length > 63 || l.startsWith('-') || l.endsWith('-')) return null;
    if (RegExp(r'^[a-z0-9-]+$').hasMatch(l)) continue;
    // A name in Cyrillic (пример.рф) is matched the way browsers send it.
    if (!RegExp(r'^[a-z0-9Ѐ-ӿ-]+$').hasMatch(l)) return null;
    labels[i] = 'xn--${punycode(l)}';
  }
  return 'domain:${labels.join('.')}';
}

/// The Punycode form of one label of a domain name (RFC 3492), without
/// the "xn--" in front.
String punycode(String label) {
  const base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700;
  final input = label.runes.toList();
  final out = StringBuffer();
  for (final c in input) {
    if (c < 0x80) out.writeCharCode(c);
  }
  final basic = out.length;
  var h = basic;
  if (basic > 0) out.write('-');
  String digit(int d) => String.fromCharCode(d < 26 ? 97 + d : 22 + d);
  int adapt(int delta, int points, bool first) {
    delta = first ? delta ~/ damp : delta ~/ 2;
    delta += delta ~/ points;
    var k = 0;
    while (delta > ((base - tMin) * tMax) ~/ 2) {
      delta ~/= base - tMin;
      k += base;
    }
    return k + (base - tMin + 1) * delta ~/ (delta + skew);
  }

  var n = 0x80, delta = 0, bias = 72;
  while (h < input.length) {
    var m = 0x7fffffff;
    for (final c in input) {
      if (c >= n && c < m) m = c;
    }
    delta += (m - n) * (h + 1);
    n = m;
    for (final c in input) {
      if (c < n) delta++;
      if (c == n) {
        var q = delta;
        for (var k = base;; k += base) {
          final t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias);
          if (q < t) break;
          out.write(digit(t + (q - t) % (base - t)));
          q = (q - t) ~/ (base - t);
        }
        out.write(digit(q));
        bias = adapt(delta, h + 1, h == basic);
        delta = 0;
        h++;
      }
    }
    delta++;
    n++;
  }
  return out.toString();
}

/// How a domain rule reads in the list: "example.com", ".рф" for the whole
/// zone, or "full:", "keyword:" and "regexp:" rules as they are.
String siteLabel(String rule) {
  var s = rule.startsWith('domain:') ? rule.substring(7) : rule;
  s = s.replaceAll('xn--p1ai', 'рф');
  return s.contains('.') || s.contains(':') ? s : '.$s';
}

/// Reads the domain rules of one category (such as "category-ru") out of a
/// geosite.dat file, in the form Xray's routing takes them.
List<String> geositeRules(Uint8List data, String code) {
  final want = code.toLowerCase();
  final out = <String>[];
  final file = _Proto(data, 0, data.length);
  while (file.more) {
    final (field, entry) = file.next();
    if (field != 1 || entry is! _Proto) continue;
    String? name;
    final domains = <_Proto>[];
    while (entry.more) {
      final (f, v) = entry.next();
      if ((f == 1 || f == 4) && v is _Proto && name == null) name = v.text.toLowerCase();
      if (f == 2 && v is _Proto) domains.add(v);
    }
    if (name != want) continue;
    for (final d in domains) {
      var type = 0;
      var value = '';
      while (d.more) {
        final (f, v) = d.next();
        if (f == 1 && v is int) type = v;
        if (f == 2 && v is _Proto) value = v.text;
      }
      if (value.isEmpty) continue;
      out.add(switch (type) {
        1 => 'regexp:$value',
        2 => 'domain:$value',
        3 => 'full:$value',
        _ => 'keyword:$value',
      });
    }
  }
  return out;
}

/// Just enough of the protobuf wire format for geosite.dat.
class _Proto {
  _Proto(this.data, this.pos, this.end);
  final Uint8List data;
  int pos;
  final int end;

  bool get more => pos < end;

  String get text => utf8.decode(Uint8List.sublistView(data, pos, end), allowMalformed: true);

  int _varint() {
    var result = 0, shift = 0;
    while (true) {
      if (pos >= end) throw const FormatException('geosite.dat is cut short');
      final b = data[pos++];
      result |= (b & 0x7f) << shift;
      if (b & 0x80 == 0) return result;
      shift += 7;
      if (shift > 63) throw const FormatException('geosite.dat has a bad number');
    }
  }

  /// The next field: its number and an int, or a [_Proto] over its bytes.
  (int, Object) next() {
    final key = _varint();
    final field = key >> 3;
    switch (key & 7) {
      case 0:
        return (field, _varint());
      case 1:
        pos += 8;
        return (field, 0);
      case 2:
        final len = _varint();
        if (len < 0 || pos + len > end) throw const FormatException('geosite.dat is cut short');
        final sub = _Proto(data, pos, pos + len);
        pos += len;
        return (field, sub);
      case 5:
        pos += 4;
        return (field, 0);
      default:
        throw const FormatException('geosite.dat is not a geosite file');
    }
  }
}
