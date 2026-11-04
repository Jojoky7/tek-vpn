import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../xray/config_builder.dart';
import 'engine.dart';

/// An installed app for the per-app VPN list.
class InstalledApp {
  const InstalledApp(this.package, this.label, this.icon);
  final String package;
  final String label;
  final Uint8List? icon;
}

/// Xray runs inside the app process, next to Android's VpnService
/// (TekVpnService.kt); this side only talks to it over channels.
class AndroidEngine extends TekEngine {
  static const _method = MethodChannel('tek/core');
  static const _events = EventChannel('tek/core/status');

  final _status = StreamController<EngineStatus>.broadcast();
  EngineStatus _current = EngineStatus.stopped;
  StreamSubscription<dynamic>? _sub;
  String _assetDir = '';

  @override
  bool get supportsModes => false;

  @override
  Stream<EngineStatus> get status => _status.stream;

  @override
  EngineStatus get current => _current;

  @override
  String get assetDir => _assetDir;

  @override
  Future<void> init(String assetDir) async {
    _assetDir = assetDir;
    _sub = _events.receiveBroadcastStream().listen((event) {
      if (event is Map) _emit(_parse(event));
    });
    final now = await _method.invokeMethod<Map<dynamic, dynamic>>('status');
    if (now != null) _emit(_parse(now));
  }

  EngineStatus _parse(Map<dynamic, dynamic> m) {
    final state = switch (m['state']) {
      'starting' => CoreState.starting,
      'running' => CoreState.running,
      'stopping' => CoreState.stopping,
      _ => CoreState.stopped,
    };
    final since = (m['since'] as num?)?.toInt() ?? 0;
    return EngineStatus(
      state,
      since: since > 0 ? DateTime.fromMillisecondsSinceEpoch(since) : null,
      error: m['error'] as String?,
      up: (m['up'] as num?)?.toInt() ?? 0,
      down: (m['down'] as num?)?.toInt() ?? 0,
      mode: TunnelMode.tun,
      serverId: m['serverId'] as String?,
    );
  }

  void _emit(EngineStatus s) {
    _current = s;
    _status.add(s);
  }

  @override
  Future<void> start(
    Map<String, dynamic> config, {
    required TunnelMode mode,
    required ConnectOptions options,
    AndroidVpnOptions android = const AndroidVpnOptions(),
    String serverName = '',
    String serverId = '',
  }) async {
    // The service answers with "running" or "stopped" a moment later.
    _emit(const EngineStatus(CoreState.starting, mode: TunnelMode.tun));
    try {
      await _method.invokeMethod('start', {
        'config': jsonEncode(config),
        'assetDir': _assetDir,
        'perAppMode': android.perAppMode,
        'packages': android.packages,
        'serverName': serverName,
        'serverId': serverId,
        'dns': XrayConfigBuilder.tunDns,
        'address': XrayConfigBuilder.tunAddress,
        'mtu': XrayConfigBuilder.tunMtu,
      });
    } on PlatformException catch (e) {
      _emit(EngineStatus(CoreState.stopped, error: e.message));
      if (e.code == 'permission_denied') throw PermissionDeniedException();
      rethrow;
    }
  }

  @override
  Future<void> stop() => _method.invokeMethod('stop');

  @override
  Future<List<PingResult>> realPing(
    Map<String, dynamic> probeConfig,
    List<String> tags, {
    String url = 'https://www.gstatic.com/generate_204',
    int timeoutMs = 5000,
    int attempts = 2,
  }) async {
    final out = await _method.invokeMethod<String>('realPing', {
      'request': jsonEncode({
        'config': probeConfig,
        'tags': tags,
        'url': url,
        'timeoutMs': timeoutMs,
        'attempts': attempts,
      }),
      'assetDir': _assetDir,
    });
    return _results(out, tags.length);
  }

  @override
  Future<List<PingResult>> tcpPing(List<({String host, int port})> targets,
      {int timeoutMs = 3000, int attempts = 2}) async {
    final out = await _method.invokeMethod<String>('tcpPing', {
      'request': jsonEncode({
        'targets': [
          for (final t in targets) {'host': t.host, 'port': t.port}
        ],
        'timeoutMs': timeoutMs,
        'attempts': attempts,
      }),
    });
    return _results(out, targets.length);
  }

  static List<PingResult> _results(String? json, int count) {
    final decoded = json == null ? null : jsonDecode(json);
    if (decoded is! List) {
      final error = decoded is Map ? decoded['error']?.toString() : 'no answer';
      return List.filled(count, PingResult(-1, error: error));
    }
    return [
      for (final r in decoded) PingResult.fromJson(Map<String, dynamic>.from(r as Map))
    ];
  }

  @override
  Future<void> cancelPing() => _method.invokeMethod('cancelPing');

  @override
  Future<List<LogLine>> logs(int sinceId) async {
    final out = await _method.invokeMethod<String>('logs', {'since': sinceId});
    final decoded = out == null ? null : jsonDecode(out);
    if (decoded is! List) return const [];
    return [
      for (final l in decoded) LogLine.fromJson(Map<String, dynamic>.from(l as Map))
    ];
  }

  @override
  Future<void> setLogLevel(String level) =>
      _method.invokeMethod('setLogLevel', {'level': level});

  @override
  Future<String?> validate(Map<String, dynamic> config) async {
    final out = await _method
        .invokeMethod<String>('validate', {'config': jsonEncode(config)});
    return (out == null || out.isEmpty) ? null : out;
  }

  @override
  Future<String> version() async =>
      await _method.invokeMethod<String>('version') ?? '';

  /// Apps with a launcher icon, for the per-app list.
  Future<List<InstalledApp>> installedApps() async {
    final list = await _method.invokeMethod<List<dynamic>>('apps') ?? const [];
    return [
      for (final a in list.cast<Map<dynamic, dynamic>>())
        InstalledApp(a['package'] as String, a['label'] as String,
            a['icon'] as Uint8List?)
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  @override
  Future<String> requestTile() async {
    try {
      return await _method.invokeMethod<String>('requestTile') ?? 'error';
    } on PlatformException {
      return 'error';
    } on MissingPluginException {
      return 'unsupported';
    }
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    await _status.close();
  }
}
