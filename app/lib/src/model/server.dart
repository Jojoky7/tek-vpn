import 'dart:convert';

/// How the first packet of a connection is cut into pieces before it goes
/// out. Some Russian providers drop VPN handshakes that arrive in one piece.
class FragmentSettings {
  const FragmentSettings({
    this.packets = 'tlshello',
    this.length = '100-200',
    this.interval = '1',
  });

  /// The values TekVPN tested with Happ in October 2026.
  static const tested = FragmentSettings();

  final String packets;
  final String length;
  final String interval;

  Map<String, dynamic> toXray() => {
        'packets': packets,
        'length': length,
        'interval': interval,
      };

  Map<String, dynamic> toJson() => toXray();

  factory FragmentSettings.fromJson(Map<String, dynamic> json) =>
      FragmentSettings(
        packets: json['packets']?.toString() ?? tested.packets,
        length: json['length']?.toString() ?? tested.length,
        interval: json['interval']?.toString() ?? tested.interval,
      );

  /// Parses the "packets,length,interval" form used in share links, such as
  /// `tlshello,100-200,10-20`.
  static FragmentSettings? tryParseLinkParam(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parts = value.split(',').map((p) => p.trim()).toList();
    if (parts.length != 3) return null;
    final range = RegExp(r'^\d+(-\d+)?$');
    if (!range.hasMatch(parts[1]) || !range.hasMatch(parts[2])) return null;
    if (parts[0] != 'tlshello' && !range.hasMatch(parts[0])) return null;
    return FragmentSettings(
        packets: parts[0], length: parts[1], interval: parts[2]);
  }

  @override
  bool operator ==(Object other) =>
      other is FragmentSettings &&
      other.packets == packets &&
      other.length == length &&
      other.interval == interval;

  @override
  int get hashCode => Object.hash(packets, length, interval);
}

/// One server (country) from a subscription.
class ServerNode {
  ServerNode({
    required this.id,
    required this.name,
    required this.countryCode,
    required this.host,
    required this.port,
    required this.protocol,
    required this.outbound,
    this.extraOutbounds = const [],
    this.fragment,
    this.hasOwnDialer = false,
  });

  /// Stable across subscription updates as long as the server is the same.
  final String id;

  /// Name without the flag emoji, e.g. "Нидерланды".
  final String name;

  /// ISO 3166 alpha-2 code in lower case, e.g. "nl"; null when unknown.
  final String? countryCode;

  final String host;
  final int port;
  final String protocol;

  /// Xray outbound without a tag.
  final Map<String, dynamic> outbound;

  /// Outbounds the server's own JSON config chains through (for example its
  /// own "fragment" outbound). Their tags are already unique.
  final List<Map<String, dynamic>> extraOutbounds;

  /// Fragmentation requested by the subscription for this server.
  final FragmentSettings? fragment;

  /// True when the server config already routes its socket through another
  /// outbound (sockopt.dialerProxy); Tek then keeps it as is.
  final bool hasOwnDialer;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'countryCode': countryCode,
        'host': host,
        'port': port,
        'protocol': protocol,
        'outbound': outbound,
        'extraOutbounds': extraOutbounds,
        if (fragment != null) 'fragment': fragment!.toJson(),
        'hasOwnDialer': hasOwnDialer,
      };

  factory ServerNode.fromJson(Map<String, dynamic> json) => ServerNode(
        id: json['id'] as String,
        name: json['name'] as String,
        countryCode: json['countryCode'] as String?,
        host: json['host'] as String,
        port: json['port'] as int,
        protocol: json['protocol'] as String,
        outbound: Map<String, dynamic>.from(json['outbound'] as Map),
        extraOutbounds: [
          for (final o in (json['extraOutbounds'] as List? ?? const []))
            Map<String, dynamic>.from(o as Map)
        ],
        fragment: json['fragment'] == null
            ? null
            : FragmentSettings.fromJson(
                Map<String, dynamic>.from(json['fragment'] as Map)),
        hasOwnDialer: json['hasOwnDialer'] as bool? ?? false,
      );

  /// Short stable id from the parts that identify a server.
  static String makeId(String protocol, String host, int port, String secret,
      String name) {
    final source = utf8.encode('$protocol|$host|$port|$secret|$name');
    // FNV-1a, 64 bit: good enough to tell servers apart, no extra package.
    var hash = 0xcbf29ce484222325;
    for (final b in source) {
      hash ^= b;
      hash *= 0x100000001b3; // wraps around at 64 bits on the Dart VM
    }
    return (hash >>> 32).toRadixString(16).padLeft(8, '0') +
        (hash & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  }
}

/// Splits a display name into its flag emoji (as a country code) and the rest.
({String? code, String name}) splitFlag(String raw) {
  final runes = raw.runes.toList();
  String? code;
  final kept = <int>[];
  for (var i = 0; i < runes.length; i++) {
    final r = runes[i];
    final isIndicator = r >= 0x1F1E6 && r <= 0x1F1FF;
    if (isIndicator &&
        i + 1 < runes.length &&
        runes[i + 1] >= 0x1F1E6 &&
        runes[i + 1] <= 0x1F1FF) {
      code ??= String.fromCharCodes(
              [r - 0x1F1E6 + 0x41, runes[i + 1] - 0x1F1E6 + 0x41])
          .toLowerCase();
      i++;
      continue;
    }
    kept.add(r);
  }
  var name = String.fromCharCodes(kept)
      .replaceAll(RegExp(r'[\u{FE0F}\u{200D}]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  name = name.replaceAll(RegExp(r'^[\-|·•:]+\s*'), '').trim();
  code ??= guessCountry(name);
  if (code == 'uk') code = 'gb';
  return (code: code, name: name.isEmpty ? raw.trim() : name);
}

const _countryWords = <String, List<String>>{
  'nl': ['нидерланд', 'голланд', 'netherlands', 'holland', 'amsterdam', 'амстердам'],
  'lv': ['латви', 'latvia', 'riga', 'рига'],
  'se': ['швеци', 'sweden', 'stockholm', 'стокгольм'],
  'gb': ['великобритан', 'англи', 'united kingdom', 'britain', 'london', 'лондон', ' uk'],
  'in': ['инди', 'india', 'mumbai', 'мумбаи', 'delhi'],
  'ru': ['росси', 'russia', 'moscow', 'москв'],
  'de': ['германи', 'germany', 'frankfurt', 'франкфурт', 'berlin'],
  'fi': ['финлянд', 'finland', 'helsinki', 'хельсинки'],
  'fr': ['франци', 'france', 'paris', 'париж'],
  'pl': ['польш', 'poland', 'warsaw', 'варшав'],
  'us': ['сша', 'usa', 'united states', 'america', 'new york', 'нью-йорк'],
  'tr': ['турци', 'turkey', 'istanbul', 'стамбул'],
  'kz': ['казахстан', 'kazakhstan', 'almaty', 'алматы'],
  'ee': ['эстони', 'estonia', 'tallinn', 'таллин'],
  'lt': ['литв', 'lithuania', 'vilnius', 'вильнюс'],
  'ch': ['швейцар', 'switzerland', 'zurich'],
  'at': ['австри', 'austria', 'vienna', 'вена'],
  'jp': ['япони', 'japan', 'tokyo', 'токио'],
  'sg': ['сингапур', 'singapore'],
  'ae': ['оаэ', 'эмират', 'emirates', 'dubai', 'дубай'],
  'ca': ['канад', 'canada', 'toronto'],
  'es': ['испани', 'spain', 'madrid'],
  'it': ['итали', 'italy', 'milan', 'милан'],
  'no': ['норвеги', 'norway', 'oslo'],
  'cz': ['чехи', 'czech', 'prague', 'праг'],
  'ge': ['грузи', 'georgia', 'tbilisi'],
  'am': ['армени', 'armenia', 'yerevan'],
  'hk': ['гонконг', 'hong kong'],
};

String? guessCountry(String name) {
  final lower = ' ${name.toLowerCase()}';
  for (final entry in _countryWords.entries) {
    for (final word in entry.value) {
      if (lower.contains(word)) return entry.key;
    }
  }
  final code = RegExp(r'\b([A-Z]{2})\b').firstMatch(name)?.group(1);
  if (code != null && _countryWords.containsKey(code.toLowerCase())) {
    return code.toLowerCase();
  }
  return null;
}
