import 'dart:convert';
import 'dart:io' show InternetAddress;

import '../model/server.dart';

/// How traffic gets into Xray.
enum TunnelMode {
  /// A virtual network card: every app goes through Tek. Android always
  /// works like this; on a computer it needs administrator rights.
  tun,

  /// The system proxy (computers only): browsers and most apps follow it.
  proxy,
}

/// The local HTTP proxy that Tek itself uses for its own requests while
/// connected. It has a random password because other apps on the device can
/// reach 127.0.0.1 too.
class ApiProxy {
  const ApiProxy(this.port, this.user, this.pass);
  final int port;
  final String user;
  final String pass;
}

class ConnectOptions {
  const ConnectOptions({
    required this.mode,
    this.ruDirect = true,
    this.fragmentation = true,
    this.blockQuic = true,
    this.socksPort = 10808,
    this.httpPort = 10809,
    this.logLevel = 'warning',
    this.geoFiles = true,
  });

  final TunnelMode mode;

  /// Russian sites and addresses go around the VPN.
  final bool ruDirect;

  /// Cut the first packet to servers into pieces (helps where providers
  /// drop VPN handshakes).
  final bool fragmentation;

  /// Block QUIC (UDP 443) so that browsers fall back to TCP, which goes
  /// through the tunnel faster.
  final bool blockQuic;

  final int socksPort;
  final int httpPort;
  final String logLevel;

  /// geoip.dat and geosite.dat are next to the core.
  final bool geoFiles;
}

/// Builds Xray configs. Every server of the subscription gets its own
/// outbound "srv-N" so that Tek can check any of them through the running
/// core; the server in use is also the "proxy" outbound.
class XrayConfigBuilder {
  XrayConfigBuilder(this.servers, {this.subscriptionFragment});

  final List<ServerNode> servers;

  /// Fragmentation the subscription asked for, if any.
  final FragmentSettings? subscriptionFragment;

  static const proxyTag = 'proxy';
  static const tunAddress = '172.19.0.1';
  static const tunDns = '172.19.0.2';
  static const tunNet = '172.19.0.0/30';
  static const tunMtu = 1500;

  static const _dnsDirect = '77.88.8.8';
  static const _dnsProxy = [
    'https://1.1.1.1/dns-query',
    'https://8.8.8.8/dns-query',
  ];

  static const _ruFallbackDomains = [
    'domain:ru',
    'domain:su',
    'domain:xn--p1ai',
  ];

  static const _privateNets = [
    '10.0.0.0/8',
    '100.64.0.0/10',
    '127.0.0.0/8',
    '169.254.0.0/16',
    '172.16.0.0/12',
    '192.168.0.0/16',
    '224.0.0.0/4',
    '255.255.255.255/32',
    'fc00::/7',
    'fe80::/10',
    '::1/128',
  ];

  /// The tag of the server's own outbound.
  String tagOf(ServerNode server) {
    final i = servers.indexWhere((s) => s.id == server.id);
    if (i < 0) throw ArgumentError('server is not in the list');
    return 'srv-$i';
  }

  /// A config for a connection through [selected].
  Map<String, dynamic> connection(ServerNode selected, ConnectOptions o,
      {ApiProxy? api}) {
    final fragments = _Fragments();
    final outbounds = <Map<String, dynamic>>[
      _serverOutbound(selected, proxyTag, fragments, o),
      for (var i = 0; i < servers.length; i++)
        _serverOutbound(servers[i], 'srv-$i', fragments, o),
      ..._extraOutbounds(),
      ...fragments.outbounds(),
      {
        'tag': 'direct',
        'protocol': 'freedom',
        'settings': {'targetStrategy': 'UseIPv4'},
      },
      {
        'tag': 'block',
        'protocol': 'blackhole',
        'settings': {
          'response': {'type': 'none'}
        },
      },
      {
        'tag': 'dns-out',
        'protocol': 'dns',
        'settings': {'nonIPQuery': 'reject'},
      },
    ];

    final sniffing = {
      'enabled': true,
      'destOverride': ['http', 'tls', 'quic'],
      'routeOnly': true,
    };
    final userInbounds = <String>[];
    final inbounds = <Map<String, dynamic>>[];
    if (o.mode == TunnelMode.tun) {
      userInbounds.add('tun-in');
      inbounds.add({
        'tag': 'tun-in',
        'protocol': 'tun',
        'settings': {'name': 'Tek', 'MTU': tunMtu},
        'sniffing': sniffing,
      });
    } else {
      userInbounds.addAll(['socks-in', 'http-in']);
      inbounds.addAll([
        {
          'tag': 'socks-in',
          'listen': '127.0.0.1',
          'port': o.socksPort,
          'protocol': 'socks',
          'settings': {'udp': true},
          'sniffing': sniffing,
        },
        {
          'tag': 'http-in',
          'listen': '127.0.0.1',
          'port': o.httpPort,
          'protocol': 'http',
          'sniffing': sniffing,
        },
      ]);
    }
    if (api != null) {
      inbounds.add({
        'tag': 'api-in',
        'listen': '127.0.0.1',
        'port': api.port,
        'protocol': 'http',
        'settings': {
          'accounts': [
            {'user': api.user, 'pass': api.pass}
          ],
        },
      });
    }

    final ruDomains =
        o.geoFiles ? const ['geosite:category-ru'] : _ruFallbackDomains;
    final rules = <Map<String, dynamic>>[
      if (api != null) {'inboundTag': ['api-in'], 'outboundTag': proxyTag},
      {
        'inboundTag': userInbounds,
        'port': '53',
        'outboundTag': 'dns-out',
      },
      {'inboundTag': ['dns-direct'], 'outboundTag': 'direct'},
      {
        'inboundTag': ['dns-proxy', 'dns-internal'],
        'outboundTag': proxyTag,
      },
      if (o.mode == TunnelMode.tun)
        // Anything else sent into the tunnel's own network, such as
        // Android's private DNS probe on port 853 or Windows' NetBIOS
        // broadcasts, fails at once instead of going out and back in.
        {'ip': ['$tunNet'], 'outboundTag': 'block'},
      {'ip': _privateNets, 'outboundTag': 'direct'},
      if (o.mode == TunnelMode.tun)
        // The servers are reached over IPv4; IPv6 is closed fast so that
        // apps switch to IPv4 instead of leaking or hanging.
        {'ip': ['::/0'], 'outboundTag': 'block'},
      if (o.ruDirect) {'domain': ruDomains, 'outboundTag': 'direct'},
      if (o.ruDirect && o.geoFiles) {'ip': ['geoip:ru'], 'outboundTag': 'direct'},
      if (o.blockQuic)
        {'network': 'udp', 'port': '443', 'outboundTag': 'block'},
      {'network': 'tcp,udp', 'outboundTag': proxyTag},
    ];

    return {
      'log': {'loglevel': o.logLevel},
      'dns': _dns(o.ruDirect ? ruDomains : const []),
      'inbounds': inbounds,
      'outbounds': outbounds,
      'routing': {'domainStrategy': 'AsIs', 'rules': rules},
      'stats': <String, dynamic>{},
      'policy': {
        'system': {
          'statsOutboundUplink': true,
          'statsOutboundDownlink': true,
        },
      },
    };
  }

  /// A config with only the servers, for checks while disconnected.
  Map<String, dynamic> probe(ConnectOptions o) {
    final fragments = _Fragments();
    return {
      'log': {'loglevel': o.logLevel},
      'dns': _dns(const []),
      'outbounds': [
        {
          'tag': 'direct',
          'protocol': 'freedom',
          'settings': {'targetStrategy': 'UseIPv4'},
        },
        for (var i = 0; i < servers.length; i++)
          _serverOutbound(servers[i], 'srv-$i', fragments, o),
        ..._extraOutbounds(),
        ...fragments.outbounds(),
      ],
      'routing': {
        'rules': [
          {
            'inboundTag': ['dns-direct', 'dns-internal'],
            'outboundTag': 'direct',
          },
        ],
      },
    };
  }

  /// Server addresses as targets for the TCP check.
  List<Map<String, dynamic>> tcpTargets() => [
        for (var i = 0; i < servers.length; i++)
          {'tag': 'srv-$i', 'host': servers[i].host, 'port': servers[i].port}
      ];

  Map<String, dynamic> _dns(List<String> directDomains) {
    final serverDomains = {
      for (final s in servers)
        if (InternetAddress.tryParse(s.host) == null) 'full:${s.host}'
    };
    final direct = [...serverDomains, ...directDomains];
    return {
      'tag': 'dns-internal',
      'queryStrategy': 'UseIPv4',
      'servers': [
        if (direct.isNotEmpty)
          {
            'address': _dnsDirect,
            'tag': 'dns-direct',
            'domains': direct,
            'skipFallback': true,
          },
        for (final url in _dnsProxy) {'address': url, 'tag': 'dns-proxy'},
      ],
    };
  }

  Map<String, dynamic> _serverOutbound(
      ServerNode s, String tag, _Fragments fragments, ConnectOptions o) {
    final out = _copy(s.outbound)..['tag'] = tag;
    final stream = Map<String, dynamic>.from(
        (out['streamSettings'] as Map?) ?? const <String, dynamic>{});
    final sockopt = Map<String, dynamic>.from(
        (stream['sockopt'] as Map?) ?? const <String, dynamic>{});
    final isDomain = InternetAddress.tryParse(s.host) == null;

    if (s.hasOwnDialer) {
      // The server's own chain stays as the subscription made it.
    } else if (o.fragmentation && _overTcp(stream)) {
      sockopt['dialerProxy'] = fragments.tagFor(
          s.fragment ?? subscriptionFragment ?? FragmentSettings.tested);
    } else if (isDomain) {
      // Resolve the server name with Xray's own DNS, never the system one,
      // which may point back into the tunnel.
      sockopt['domainStrategy'] = 'UseIPv4';
    }
    if (sockopt.isNotEmpty) stream['sockopt'] = sockopt;
    if (stream.isNotEmpty) out['streamSettings'] = stream;
    return out;
  }

  List<Map<String, dynamic>> _extraOutbounds() {
    final seen = <String>{};
    return [
      for (final s in servers)
        for (final o in s.extraOutbounds)
          if (seen.add(o['tag'] as String)) _copy(o)
    ];
  }

  static bool _overTcp(Map<String, dynamic> stream) {
    final network = (stream['network'] ?? 'raw').toString();
    if (network == 'kcp' || network == 'mkcp' || network == 'quic') {
      return false;
    }
    final tls = stream['tlsSettings'];
    if (tls is Map && tls['alpn'] is List) {
      final alpn = (tls['alpn'] as List).map((e) => e.toString()).toList();
      if (alpn.length == 1 && alpn.first == 'h3') return false;
    }
    return true;
  }

  static Map<String, dynamic> _copy(Map<String, dynamic> m) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(m)) as Map);
}

/// One "fragment" outbound per distinct set of values.
class _Fragments {
  final _tags = <FragmentSettings, String>{};

  String tagFor(FragmentSettings f) => _tags.putIfAbsent(
      f, () => _tags.isEmpty ? 'fragment' : 'fragment-${_tags.length}');

  List<Map<String, dynamic>> outbounds() => [
        for (final e in _tags.entries)
          {
            'tag': e.value,
            'protocol': 'freedom',
            'settings': {
              'targetStrategy': 'UseIPv4',
              'fragment': e.key.toXray(),
            },
            'streamSettings': {
              'sockopt': {'tcpNoDelay': true},
            },
          }
      ];
}
