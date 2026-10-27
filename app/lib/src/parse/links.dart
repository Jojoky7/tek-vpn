import 'dart:convert';

import '../model/server.dart';
import 'base64.dart';

/// Thrown for a share link Tek cannot use.
class LinkException implements Exception {
  LinkException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The pieces of a `scheme://user@host:port?query#name` share link. Parsed
/// by hand because real links often carry unescaped emoji, spaces or JSON
/// that a strict URI parser rejects.
class SplitLink {
  SplitLink(this.scheme, this.userInfo, this.host, this.port, this.query,
      this.name);

  final String scheme;
  final String userInfo;
  final String host;
  final int port;
  final Map<String, String> query;
  final String name;

  static String _decode(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }

  static SplitLink parse(String link, {int defaultPort = 443}) {
    final schemeEnd = link.indexOf('://');
    if (schemeEnd <= 0) throw LinkException('not a link');
    final scheme = link.substring(0, schemeEnd).toLowerCase();
    var rest = link.substring(schemeEnd + 3);

    var name = '';
    final hash = rest.indexOf('#');
    if (hash >= 0) {
      name = _decode(rest.substring(hash + 1)).trim();
      rest = rest.substring(0, hash);
    }
    final query = <String, String>{};
    final q = rest.indexOf('?');
    if (q >= 0) {
      for (final pair in rest.substring(q + 1).split('&')) {
        if (pair.isEmpty) continue;
        final eq = pair.indexOf('=');
        final key = eq < 0 ? pair : pair.substring(0, eq);
        final value = eq < 0 ? '' : pair.substring(eq + 1);
        query[_decode(key)] = _decode(value);
      }
      rest = rest.substring(0, q);
    }
    if (rest.endsWith('/')) rest = rest.substring(0, rest.length - 1);

    var userInfo = '';
    final at = rest.lastIndexOf('@');
    if (at >= 0) {
      userInfo = _decode(rest.substring(0, at));
      rest = rest.substring(at + 1);
    }

    String host;
    var port = defaultPort;
    if (rest.startsWith('[')) {
      final close = rest.indexOf(']');
      if (close < 0) throw LinkException('bad IPv6 address');
      host = rest.substring(1, close);
      final after = rest.substring(close + 1);
      if (after.startsWith(':')) port = int.tryParse(after.substring(1)) ?? -1;
    } else {
      final colon = rest.lastIndexOf(':');
      if (colon >= 0) {
        host = rest.substring(0, colon);
        port = int.tryParse(rest.substring(colon + 1)) ?? -1;
      } else {
        host = rest;
      }
    }
    if (host.isEmpty) throw LinkException('no server address');
    if (port <= 0 || port > 65535) throw LinkException('bad port');
    return SplitLink(scheme, userInfo, host, port, query, name);
  }
}

String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;

/// Builds Xray streamSettings from share-link parameters, following the
/// Xray share-link standard (XTLS/Xray-core discussion #716).
Map<String, dynamic> streamFromQuery(Map<String, String> q, String address,
    {String defaultSecurity = 'none'}) {
  var network = (q['type'] ?? 'raw').toLowerCase();
  switch (network) {
    case 'tcp':
      network = 'raw';
    case 'splithttp':
      network = 'xhttp';
    case 'h2':
    case 'http':
    case 'quic':
      throw LinkException('transport "$network" is not supported by Xray 26');
  }
  final stream = <String, dynamic>{'network': network};
  final host = _nonEmpty(q['host']);
  final path = _nonEmpty(q['path']);

  switch (network) {
    case 'raw':
      if (q['headerType'] == 'http') {
        stream['rawSettings'] = {
          'header': {
            'type': 'http',
            'request': {
              'path': (path ?? '/').split(','),
              if (host != null) 'headers': {'Host': host.split(',')},
            },
          },
        };
      }
    case 'ws':
      stream['wsSettings'] = {
        'path': path ?? '/',
        'host': ?host,
      };
    case 'httpupgrade':
      stream['httpupgradeSettings'] = {
        'path': path ?? '/',
        'host': ?host,
      };
    case 'grpc':
      stream['grpcSettings'] = {
        'serviceName': q['serviceName'] ?? path ?? '',
        'multiMode': q['mode'] == 'multi',
        if (_nonEmpty(q['authority']) != null) 'authority': q['authority'],
      };
    case 'kcp':
      stream['kcpSettings'] = {
        if (_nonEmpty(q['mtu']) != null) 'mtu': int.tryParse(q['mtu']!),
        if (_nonEmpty(q['tti']) != null) 'tti': int.tryParse(q['tti']!),
      };
    case 'xhttp':
      final xhttp = <String, dynamic>{
        'path': path ?? '/',
        'mode': _nonEmpty(q['mode']) ?? 'auto',
      };
      if (host != null) xhttp['host'] = host;
      final extra = _nonEmpty(q['extra']);
      if (extra != null) {
        try {
          xhttp['extra'] = jsonDecode(extra);
        } catch (_) {
          throw LinkException('bad XHTTP "extra"');
        }
      }
      stream['xhttpSettings'] = xhttp;
    default:
      throw LinkException('unknown transport "$network"');
  }

  final security = (q['security'] ?? defaultSecurity).toLowerCase();
  final sni = _nonEmpty(q['sni']) ?? _nonEmpty(q['peer']);
  final fp = _nonEmpty(q['fp']);
  switch (security) {
    case 'none':
    case '':
      break;
    case 'tls':
      stream['security'] = 'tls';
      stream['tlsSettings'] = {
        'serverName': sni ?? host ?? address,
        'fingerprint': fp ?? 'chrome',
        if (_nonEmpty(q['alpn']) != null) 'alpn': q['alpn']!.split(','),
        if (q['allowInsecure'] == '1' ||
            q['allowInsecure'] == 'true' ||
            q['insecure'] == '1')
          'allowInsecure': true,
        if (_nonEmpty(q['ech']) != null) 'echConfigList': q['ech'],
      };
    case 'reality':
      final pbk = _nonEmpty(q['pbk']);
      if (pbk == null) throw LinkException('REALITY link without public key');
      stream['security'] = 'reality';
      stream['realitySettings'] = {
        'serverName': sni ?? address,
        'fingerprint': fp ?? 'chrome',
        'publicKey': pbk,
        'shortId': q['sid'] ?? '',
        'spiderX': q['spx'] ?? '',
        if (_nonEmpty(q['pqv']) != null) 'mldsa65Verify': q['pqv'],
      };
    default:
      throw LinkException('unknown security "$security"');
  }
  return stream;
}

ServerNode _node(String protocol, SplitLink l, String secret,
    Map<String, dynamic> outbound, String fallbackName) {
  final split = splitFlag(l.name.isEmpty ? fallbackName : l.name);
  return ServerNode(
    id: ServerNode.makeId(protocol, l.host, l.port, secret, l.name),
    name: split.name,
    countryCode: split.code,
    host: l.host,
    port: l.port,
    protocol: protocol,
    outbound: outbound,
    fragment: FragmentSettings.tryParseLinkParam(l.query['fragment']),
  );
}

ServerNode parseVless(String link) {
  final l = SplitLink.parse(link);
  if (l.userInfo.isEmpty) throw LinkException('VLESS link without id');
  final user = <String, dynamic>{
    'id': l.userInfo,
    'encryption': _nonEmpty(l.query['encryption']) ?? 'none',
  };
  final flow = _nonEmpty(l.query['flow']);
  if (flow != null) user['flow'] = flow;
  final outbound = {
    'protocol': 'vless',
    'settings': {
      'vnext': [
        {
          'address': l.host,
          'port': l.port,
          'users': [user],
        }
      ],
    },
    'streamSettings': streamFromQuery(l.query, l.host),
  };
  return _node('vless', l, l.userInfo, outbound, '${l.host}:${l.port}');
}

ServerNode parseTrojan(String link) {
  final l = SplitLink.parse(link);
  if (l.userInfo.isEmpty) throw LinkException('Trojan link without password');
  final outbound = {
    'protocol': 'trojan',
    'settings': {
      'servers': [
        {'address': l.host, 'port': l.port, 'password': l.userInfo}
      ],
    },
    'streamSettings': streamFromQuery(l.query, l.host, defaultSecurity: 'tls'),
  };
  return _node('trojan', l, l.userInfo, outbound, '${l.host}:${l.port}');
}

ServerNode parseShadowsocks(String link) {
  // SIP002: ss://base64url(method:password)@host:port#name, or the older
  // ss://base64(method:password@host:port)#name.
  var body = link.substring('ss://'.length);
  var name = '';
  final hash = body.indexOf('#');
  if (hash >= 0) {
    name = body.substring(hash + 1);
    body = body.substring(0, hash);
  }
  final q = body.indexOf('?');
  if (q >= 0) {
    final query = body.substring(q + 1);
    if (query.contains('plugin=')) {
      throw LinkException('Shadowsocks plugins are not supported');
    }
    body = body.substring(0, q);
  }
  if (!body.contains('@')) {
    final decoded = tryDecodeBase64(body);
    if (decoded == null) throw LinkException('bad Shadowsocks link');
    body = decoded;
  }
  final at = body.lastIndexOf('@');
  if (at < 0) throw LinkException('bad Shadowsocks link');
  var userInfo = body.substring(0, at);
  if (!userInfo.contains(':')) {
    userInfo = tryDecodeBase64(Uri.decodeComponent(userInfo)) ?? userInfo;
  } else {
    userInfo = Uri.decodeComponent(userInfo);
  }
  final colon = userInfo.indexOf(':');
  if (colon < 0) throw LinkException('bad Shadowsocks credentials');
  final method = userInfo.substring(0, colon);
  final password = userInfo.substring(colon + 1);
  final l = SplitLink.parse(
      'ss://x@${body.substring(at + 1)}${name.isEmpty ? '' : '#$name'}');
  final outbound = {
    'protocol': 'shadowsocks',
    'settings': {
      'servers': [
        {
          'address': l.host,
          'port': l.port,
          'method': method,
          'password': password,
        }
      ],
    },
  };
  return _node('shadowsocks', l, password, outbound, '${l.host}:${l.port}');
}

ServerNode parseVmess(String link) {
  final body = link.substring('vmess://'.length);
  if (body.contains('@')) {
    // AEAD form: vmess://uuid@host:port?...
    final l = SplitLink.parse(link);
    final outbound = {
      'protocol': 'vmess',
      'settings': {
        'vnext': [
          {
            'address': l.host,
            'port': l.port,
            'users': [
              {
                'id': l.userInfo,
                'security': _nonEmpty(l.query['encryption']) ?? 'auto',
              }
            ],
          }
        ],
      },
      'streamSettings': streamFromQuery(l.query, l.host),
    };
    return _node('vmess', l, l.userInfo, outbound, '${l.host}:${l.port}');
  }
  // Legacy form: vmess://base64(json)
  final decoded = tryDecodeBase64(body.split('#').first);
  if (decoded == null) throw LinkException('bad VMess link');
  final Map<String, dynamic> j;
  try {
    j = Map<String, dynamic>.from(jsonDecode(decoded) as Map);
  } catch (_) {
    throw LinkException('bad VMess link');
  }
  String s(String key) => j[key]?.toString() ?? '';
  final host = s('add');
  final port = int.tryParse(s('port')) ?? 0;
  if (host.isEmpty || port <= 0) throw LinkException('bad VMess address');
  final query = <String, String>{
    'type': s('net').isEmpty ? 'raw' : s('net'),
    if (s('type').isNotEmpty) 'headerType': s('type'),
    if (s('host').isNotEmpty) 'host': s('host'),
    if (s('path').isNotEmpty) 'path': s('path'),
    if (s('tls').isNotEmpty) 'security': s('tls'),
    if (s('sni').isNotEmpty) 'sni': s('sni'),
    if (s('alpn').isNotEmpty) 'alpn': s('alpn'),
    if (s('fp').isNotEmpty) 'fp': s('fp'),
    if (s('net') == 'grpc' && s('path').isNotEmpty) 'serviceName': s('path'),
  };
  final l = SplitLink('vmess', s('id'), host, port, query, s('ps'));
  final outbound = {
    'protocol': 'vmess',
    'settings': {
      'vnext': [
        {
          'address': host,
          'port': port,
          'users': [
            {
              'id': s('id'),
              'security': s('scy').isEmpty ? 'auto' : s('scy'),
            }
          ],
        }
      ],
    },
    'streamSettings': streamFromQuery(query, host),
  };
  return _node('vmess', l, s('id'), outbound, '$host:$port');
}

/// Parses one share link; throws [LinkException] when it cannot be used.
ServerNode parseShareLink(String link) {
  final trimmed = link.trim();
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('vless://')) return parseVless(trimmed);
  if (lower.startsWith('trojan://')) return parseTrojan(trimmed);
  if (lower.startsWith('ss://')) return parseShadowsocks(trimmed);
  if (lower.startsWith('vmess://')) return parseVmess(trimmed);
  final scheme = trimmed.split('://').first;
  throw LinkException('"$scheme" links are not supported');
}
