import 'dart:convert';

import '../model/server.dart';
import '../model/subscription.dart';
import 'base64.dart';
import 'links.dart';

/// What came out of one subscription download.
class ParsedSubscription {
  ParsedSubscription(this.info, this.servers, this.skipped);

  final SubscriptionInfo info;
  final List<ServerNode> servers;

  /// Entries Tek could not use, with the reason, for the log.
  final List<String> skipped;
}

/// Thrown when the body is not a subscription at all (an HTML page, an
/// error text, an empty answer).
class SubscriptionFormatException implements Exception {
  SubscriptionFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

const _proxyProtocols = {'vless', 'vmess', 'trojan', 'shadowsocks'};

/// Reads the subscription headers that Happ, v2rayN and Marzban use.
/// Header names must be in lower case.
SubscriptionInfo infoFromHeaders(Map<String, String> headers) {
  final b = _InfoBuilder();
  headers.forEach(b.add);
  return b.build();
}

/// Parses a subscription body: base64 or plain share links, one per line,
/// or Xray JSON (one config or a list of them). `#key: value` lines in the
/// body work like headers and override them.
ParsedSubscription parseSubscription(String body,
    {Map<String, String> headers = const {}}) {
  final info = _InfoBuilder();
  headers.forEach(info.add);

  var text = body.replaceAll('﻿', '').trim();
  if (text.isEmpty) {
    throw SubscriptionFormatException('the subscription is empty');
  }
  if (!_looksLikeJson(text) && !text.contains('://')) {
    final decoded = tryDecodeBase64(text);
    if (decoded != null) text = decoded.replaceAll('﻿', '').trim();
  }
  if (_looksLikeHtml(text)) {
    throw SubscriptionFormatException('the link opens a web page, not a subscription');
  }

  final servers = <ServerNode>[];
  final skipped = <String>[];
  if (_looksLikeJson(text)) {
    _parseJsonBody(text, servers, skipped);
  } else {
    _parseLines(text, info, servers, skipped);
  }

  final unique = <String, ServerNode>{};
  for (final s in servers) {
    unique.putIfAbsent(s.id, () => s);
  }
  if (unique.isEmpty) {
    throw SubscriptionFormatException(skipped.isEmpty
        ? 'no servers in the subscription'
        : 'no usable servers in the subscription: ${skipped.first}');
  }
  return ParsedSubscription(info.build(), unique.values.toList(), skipped);
}

bool _looksLikeJson(String s) => s.startsWith('{') || s.startsWith('[');

bool _looksLikeHtml(String s) {
  final head = s.length > 200 ? s.substring(0, 200) : s;
  final lower = head.toLowerCase();
  return lower.startsWith('<!doctype') ||
      lower.startsWith('<html') ||
      lower.contains('<head>') ||
      lower.contains('<body');
}

void _parseLines(String text, _InfoBuilder info, List<ServerNode> servers,
    List<String> skipped) {
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#') || line.startsWith('//')) {
      final meta = line.replaceFirst(RegExp(r'^(#|//)\s*'), '');
      final colon = meta.indexOf(':');
      if (colon > 0) {
        info.add(meta.substring(0, colon).trim().toLowerCase(),
            meta.substring(colon + 1).trim());
      }
      continue;
    }
    if (line.contains('://')) {
      _addLink(line, servers, skipped);
      continue;
    }
    // Some panels encode each line on its own.
    final decoded = tryDecodeBase64(line);
    if (decoded != null && decoded.contains('://')) {
      for (final inner in const LineSplitter().convert(decoded)) {
        if (inner.trim().contains('://')) _addLink(inner, servers, skipped);
      }
    }
  }
}

void _addLink(String link, List<ServerNode> servers, List<String> skipped) {
  try {
    servers.add(parseShareLink(link));
  } on LinkException catch (e) {
    skipped.add('${_scheme(link)}: ${e.message}');
  } catch (e) {
    skipped.add('${_scheme(link)}: $e');
  }
}

String _scheme(String link) {
  final i = link.indexOf('://');
  return i > 0 ? link.substring(0, i) : 'link';
}

void _parseJsonBody(
    String text, List<ServerNode> servers, List<String> skipped) {
  final dynamic json;
  try {
    json = jsonDecode(text);
  } catch (_) {
    throw SubscriptionFormatException('the subscription is broken JSON');
  }
  final configs = json is List ? json : [json];
  for (var i = 0; i < configs.length; i++) {
    final c = configs[i];
    if (c is! Map) continue;
    try {
      final node = serverFromXrayConfig(Map<String, dynamic>.from(c), i);
      if (node != null) servers.add(node);
    } on LinkException catch (e) {
      skipped.add('config ${i + 1}: ${e.message}');
    }
  }
}

/// Takes the proxy outbound out of a full Xray config, together with the
/// outbounds it chains through. Returns null for configs without a proxy
/// (for example a config that only routes).
ServerNode? serverFromXrayConfig(Map<String, dynamic> config, int index) {
  final outbounds = [
    for (final o in (config['outbounds'] as List? ?? const []))
      if (o is Map) Map<String, dynamic>.from(o)
  ];
  if (outbounds.isEmpty) return null;
  final byTag = <String, Map<String, dynamic>>{
    for (final o in outbounds)
      if (o['tag'] is String) o['tag'] as String: o
  };
  final main = byTag['proxy'] ??
      outbounds.firstWhere(
          (o) => _proxyProtocols.contains(o['protocol']),
          orElse: () => const {});
  if (main.isEmpty) return null;
  final protocol = main['protocol']?.toString() ?? '';
  if (!_proxyProtocols.contains(protocol)) {
    throw LinkException('protocol "$protocol" is not supported');
  }

  final address = _serverAddress(main);
  if (address == null) throw LinkException('no server address');
  final secret = _serverSecret(main);
  final rawName = (config['remarks'] ?? config['remark'] ?? config['ps'] ?? '')
      .toString()
      .trim();
  final split = splitFlag(rawName.isEmpty
      ? '${address.host}:${address.port}'
      : rawName);
  final id = ServerNode.makeId(
      protocol, address.host, address.port, secret, rawName);

  // Walk the dialerProxy / proxySettings chain from the main outbound.
  final chain = <Map<String, dynamic>>[];
  final seen = <String>{};
  var current = main;
  FragmentSettings? fragment;
  while (true) {
    final next = _chainedTag(current);
    if (next == null || seen.contains(next)) break;
    seen.add(next);
    final o = byTag[next];
    if (o == null) break;
    chain.add(o);
    current = o;
  }

  final outbound = _deepCopy(main)..remove('tag');
  final extra = <Map<String, dynamic>>[];
  var ownDialer = false;
  if (chain.length == 1 && _isPlainFragment(chain.first)) {
    // The usual case: the server only asks for fragmentation. Tek keeps
    // the values and applies them its own way, so the switch in the
    // settings still works.
    fragment = FragmentSettings.fromJson(Map<String, dynamic>.from(
        (chain.first['settings'] as Map)['fragment'] as Map));
    _removeChainRef(outbound);
  } else if (chain.isNotEmpty) {
    ownDialer = true;
    final rename = <String, String>{
      for (final o in chain) o['tag'] as String: 'x$id-${o['tag']}'
    };
    _renameChainRef(outbound, rename);
    for (final o in chain) {
      final copy = _deepCopy(o)..['tag'] = rename[o['tag']]!;
      _renameChainRef(copy, rename);
      extra.add(copy);
    }
  }

  return ServerNode(
    id: id,
    name: split.name,
    countryCode: split.code,
    host: address.host,
    port: address.port,
    protocol: protocol,
    outbound: outbound,
    extraOutbounds: extra,
    fragment: fragment,
    hasOwnDialer: ownDialer,
  );
}

({String host, int port})? _serverAddress(Map<String, dynamic> o) {
  final settings = o['settings'];
  if (settings is! Map) return null;
  Map? entry;
  if (settings['vnext'] is List && (settings['vnext'] as List).isNotEmpty) {
    entry = (settings['vnext'] as List).first as Map?;
  } else if (settings['servers'] is List &&
      (settings['servers'] as List).isNotEmpty) {
    entry = (settings['servers'] as List).first as Map?;
  } else if (settings['address'] != null) {
    entry = settings;
  }
  if (entry == null) return null;
  final host = entry['address']?.toString() ?? '';
  final port = int.tryParse(entry['port']?.toString() ?? '') ?? 0;
  if (host.isEmpty || port <= 0 || port > 65535) return null;
  return (host: host, port: port);
}

String _serverSecret(Map<String, dynamic> o) {
  final settings = o['settings'];
  if (settings is! Map) return '';
  if (settings['vnext'] is List && (settings['vnext'] as List).isNotEmpty) {
    final users = ((settings['vnext'] as List).first as Map)['users'];
    if (users is List && users.isNotEmpty) {
      return (users.first as Map)['id']?.toString() ?? '';
    }
  }
  if (settings['servers'] is List && (settings['servers'] as List).isNotEmpty) {
    final s = (settings['servers'] as List).first as Map;
    return (s['password'] ?? s['id'] ?? '').toString();
  }
  return (settings['id'] ?? settings['password'] ?? '').toString();
}

String? _chainedTag(Map<String, dynamic> o) {
  final stream = o['streamSettings'];
  if (stream is Map) {
    final sockopt = stream['sockopt'];
    if (sockopt is Map && sockopt['dialerProxy'] is String) {
      final tag = sockopt['dialerProxy'] as String;
      if (tag.isNotEmpty) return tag;
    }
  }
  final proxySettings = o['proxySettings'];
  if (proxySettings is Map && proxySettings['tag'] is String) {
    final tag = proxySettings['tag'] as String;
    if (tag.isNotEmpty) return tag;
  }
  return null;
}

bool _isPlainFragment(Map<String, dynamic> o) {
  if (o['protocol'] != 'freedom') return false;
  final settings = o['settings'];
  if (settings is! Map || settings['fragment'] is! Map) return false;
  return _chainedTag(o) == null;
}

void _removeChainRef(Map<String, dynamic> o) {
  final stream = o['streamSettings'];
  if (stream is Map && stream['sockopt'] is Map) {
    (stream['sockopt'] as Map).remove('dialerProxy');
    if ((stream['sockopt'] as Map).isEmpty) stream.remove('sockopt');
  }
  o.remove('proxySettings');
}

void _renameChainRef(Map<String, dynamic> o, Map<String, String> rename) {
  final stream = o['streamSettings'];
  if (stream is Map && stream['sockopt'] is Map) {
    final sockopt = stream['sockopt'] as Map;
    final tag = sockopt['dialerProxy'];
    if (tag is String && rename.containsKey(tag)) {
      sockopt['dialerProxy'] = rename[tag];
    }
  }
  final proxySettings = o['proxySettings'];
  if (proxySettings is Map) {
    final tag = proxySettings['tag'];
    if (tag is String && rename.containsKey(tag)) {
      proxySettings['tag'] = rename[tag];
    }
  }
}

Map<String, dynamic> _deepCopy(Map<String, dynamic> m) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(m)) as Map);

class _InfoBuilder {
  String? title;
  int? upload, download, total, interval;
  DateTime? expire;
  String? support, page, announce;
  bool? fragOn;
  String? fragPackets, fragLength, fragInterval;

  void add(String key, String value) {
    final v = value.trim();
    switch (key) {
      case 'subscription-userinfo':
        for (final part in v.split(';')) {
          final eq = part.indexOf('=');
          if (eq < 0) continue;
          final k = part.substring(0, eq).trim().toLowerCase();
          final n = int.tryParse(part.substring(eq + 1).trim().split('.').first);
          if (n == null) continue;
          switch (k) {
            case 'upload':
              upload = n;
            case 'download':
              download = n;
            case 'total':
              total = n;
            case 'expire':
              expire = n > 0
                  ? DateTime.fromMillisecondsSinceEpoch(n * 1000)
                  : null;
          }
        }
      case 'profile-title':
        title = _text(v);
      case 'profile-update-interval':
        final hours = int.tryParse(v);
        if (hours != null && hours > 0) interval = hours;
      case 'support-url':
        support = _url(v);
      case 'profile-web-page-url':
        page = _url(v);
      case 'announce':
        announce = _text(v);
      case 'fragmentation-enable':
        fragOn = v == '1' || v.toLowerCase() == 'true';
      case 'fragmentation-packets':
        fragPackets = v;
      case 'fragmentation-length':
        fragLength = v;
      case 'fragmentation-interval':
        fragInterval = v;
    }
  }

  static String? _text(String v) {
    if (v.isEmpty) return null;
    if (v.startsWith('base64:')) {
      return tryDecodeBase64(v.substring(7))?.trim();
    }
    return v;
  }

  static String? _url(String v) {
    final uri = Uri.tryParse(v);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http') ||
        uri.isScheme('tg'))) {
      return null;
    }
    return v;
  }

  SubscriptionInfo build() {
    FragmentSettings? fragment;
    if (fragOn == true) {
      fragment = FragmentSettings(
        packets: fragPackets ?? FragmentSettings.tested.packets,
        length: fragLength ?? FragmentSettings.tested.length,
        interval: fragInterval ?? FragmentSettings.tested.interval,
      );
    }
    return SubscriptionInfo(
      title: title,
      upload: upload,
      download: download,
      total: total,
      expire: expire,
      updateIntervalHours: interval,
      supportUrl: support,
      webPageUrl: page,
      announce: announce,
      fragment: fragment,
    );
  }
}
