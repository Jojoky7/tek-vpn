import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../xray/config_builder.dart';
import 'elevate.dart';
import 'engine.dart';

class _CoreInfo {
  _CoreInfo(this.port, this.pid, this.elevated, this.token);
  final int port;
  final int pid;
  final bool elevated;
  final String token;
}

/// Windows and macOS: Xray runs in "tek-core", a background process that the
/// app starts and talks to over HTTP on 127.0.0.1 with a random token. For
/// the "all traffic" mode the core is started again with administrator
/// rights.
class DesktopEngine extends TekEngine {
  DesktopEngine(this.dataDir);

  /// Folder for the core's runtime files.
  final String dataDir;

  final _status = StreamController<EngineStatus>.broadcast();
  EngineStatus _current = EngineStatus.stopped;
  _CoreInfo? _core;
  Future<_CoreInfo>? _launching;
  Timer? _poll;
  String _assetDir = '';
  String _logLevel = 'warning';
  final _http = HttpClient()..findProxy = (_) => 'DIRECT';

  @override
  bool get supportsModes => true;

  @override
  Stream<EngineStatus> get status => _status.stream;

  @override
  EngineStatus get current => _current;

  @override
  String get assetDir => _assetDir;

  @override
  bool get elevated => _core?.elevated ?? false;

  static String get corePath {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final name = Platform.isWindows ? 'tek-core.exe' : 'tek-core';
    return '$exeDir${Platform.pathSeparator}$name';
  }

  @override
  Future<void> init(String assetDir) async {
    _assetDir = assetDir;
    await Directory(dataDir).create(recursive: true);
    if (Platform.isMacOS) {
      // A downloaded app comes with every file marked as quarantined. The
      // person has already allowed Tek itself, so the mark is taken off the
      // core it starts; otherwise macOS could block it again.
      try {
        await Process.run('/usr/bin/xattr', ['-d', 'com.apple.quarantine', corePath]);
      } catch (_) {}
    }
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _refresh());
  }

  Future<_CoreInfo> _ensureCore({bool elevated = false}) async {
    final core = _core;
    if (core != null && (!elevated || core.elevated)) return core;
    final launching = _launching;
    if (launching != null) return launching;
    final f = _launch(elevated: elevated);
    _launching = f;
    try {
      final info = await f;
      if (core != null && core != info) {
        // The old core without rights is not needed any more.
        unawaited(_call(core, 'POST', '/v1/shutdown').catchError((_) => null));
      }
      _core = info;
      return info;
    } finally {
      _launching = null;
    }
  }

  Future<_CoreInfo> _launch({required bool elevated}) async {
    final exe = corePath;
    if (!File(exe).existsSync()) {
      throw StateError('tek-core is missing next to the app: $exe');
    }
    final rnd = Random.secure();
    final token =
        List.generate(32, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'))
            .join();
    final tag = List.generate(6, (_) => rnd.nextInt(36).toRadixString(36)).join();
    final sep = Platform.pathSeparator;
    final tokenFile = File('$dataDir${sep}token-$tag');
    final readyFile = File('$dataDir${sep}ready-$tag.json');
    await tokenFile.writeAsString(token, flush: true);
    final args = [
      'serve',
      '-data', dataDir,
      '-token-file', tokenFile.path,
      '-ready-file', readyFile.path,
      '-parent', '$pid',
      '-log-level', _logLevel,
    ];
    try {
      if (elevated) {
        await runElevated(exe, args);
      } else {
        await Process.start(exe, args, mode: ProcessStartMode.detachedWithStdio)
            .then((p) {
          p.stdout.drain<void>();
          p.stderr.drain<void>();
        });
      }
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (DateTime.now().isBefore(deadline)) {
        if (readyFile.existsSync()) {
          final j = jsonDecode(await readyFile.readAsString()) as Map;
          await readyFile.delete().catchError((_) => readyFile);
          return _CoreInfo((j['port'] as num).toInt(), (j['pid'] as num).toInt(),
              j['elevated'] == true, token);
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      throw TimeoutException('tek-core did not start');
    } finally {
      if (tokenFile.existsSync()) {
        await tokenFile.delete().catchError((_) => tokenFile);
      }
    }
  }

  Future<dynamic> _call(_CoreInfo core, String method, String path,
      [Object? body]) async {
    final req = await _http
        .openUrl(method, Uri.parse('http://127.0.0.1:${core.port}$path'))
        .timeout(const Duration(seconds: 5));
    req.headers.set('Authorization', 'Bearer ${core.token}');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final resp = await req.close();
    final text = await resp.transform(utf8.decoder).join();
    final decoded = text.isEmpty ? null : jsonDecode(text);
    if (resp.statusCode != 200) {
      final error = decoded is Map ? decoded['error']?.toString() : null;
      throw CoreError(error ?? 'HTTP ${resp.statusCode}');
    }
    return decoded;
  }

  /// Calls the core; if it has died, forgets it so the next call starts a
  /// new one.
  Future<dynamic> _request(String method, String path, [Object? body]) async {
    final core = await _ensureCore();
    try {
      return await _call(core, method, path, body);
    } on SocketException {
      if (_core == core) _core = null;
      rethrow;
    }
  }

  Future<void> _refresh() async {
    final core = _core;
    if (core == null) return;
    try {
      final s = await _call(core, 'GET', '/v1/status') as Map;
      _emitFrom(s);
    } on SocketException {
      if (_core == core) {
        _core = null;
        if (_current.state != CoreState.stopped) {
          _emit(const EngineStatus(CoreState.stopped,
              error: 'the connection service stopped unexpectedly'));
        }
      }
    } catch (_) {
      // A slow answer is not a reason to change anything.
    }
  }

  void _emitFrom(Map<dynamic, dynamic> s) {
    if (_current.state == CoreState.starting || _current.state == CoreState.stopping) {
      return; // start() and stop() report their own outcome
    }
    final running = s['running'] == true;
    final since = (s['since'] as num?)?.toInt() ?? 0;
    _emit(EngineStatus(
      running ? CoreState.running : CoreState.stopped,
      since: since > 0 ? DateTime.fromMillisecondsSinceEpoch(since) : null,
      up: (s['up'] as num?)?.toInt() ?? 0,
      down: (s['down'] as num?)?.toInt() ?? 0,
      mode: switch (s['mode']) {
        'tun' => TunnelMode.tun,
        'proxy' => TunnelMode.proxy,
        _ => null,
      },
      error: running ? null : _current.error,
    ));
  }

  void _emit(EngineStatus s) {
    _current = s;
    if (!_status.isClosed) _status.add(s);
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
    final core = await _ensureCore();
    if (mode == TunnelMode.tun && !core.elevated) throw NeedsAdminException();
    _emit(EngineStatus(CoreState.starting, mode: mode));
    final body = {
      'config': config,
      'mode': mode == TunnelMode.tun ? 'tun' : 'proxy',
      'assetDir': _assetDir,
      if (mode == TunnelMode.proxy)
        'systemProxy': {
          'httpPort': options.httpPort,
          'socksPort': options.socksPort,
          'bypass': const [
            'localhost',
            '127.*',
            '10.*',
            '172.16.*', '172.17.*', '172.18.*', '172.19.*', '172.20.*',
            '172.21.*', '172.22.*', '172.23.*', '172.24.*', '172.25.*',
            '172.26.*', '172.27.*', '172.28.*', '172.29.*', '172.30.*',
            '172.31.*',
            '192.168.*',
            '*.local',
          ],
        },
      if (mode == TunnelMode.tun)
        'tun': {
          'mtu': XrayConfigBuilder.tunMtu,
          'address': '${XrayConfigBuilder.tunAddress}/30',
          'dns': XrayConfigBuilder.tunDns,
          'ipv6': true,
        },
    };
    try {
      final s = await _call(core, 'POST', '/v1/start', body) as Map;
      _current = EngineStatus(CoreState.stopped, mode: mode);
      _emitFrom(s);
    } on CoreError catch (e) {
      _emit(EngineStatus(CoreState.stopped, error: e.message));
      if (e.message == 'needs_admin') throw NeedsAdminException();
      rethrow;
    } catch (e) {
      _emit(EngineStatus(CoreState.stopped, error: e.toString()));
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    final core = _core;
    if (core == null) {
      _emit(EngineStatus.stopped);
      return;
    }
    _emit(EngineStatus(CoreState.stopping, mode: _current.mode));
    try {
      final s = await _call(core, 'POST', '/v1/stop') as Map;
      _current = EngineStatus.stopped;
      _emitFrom(s);
    } catch (_) {
      _emit(EngineStatus.stopped);
    }
  }

  @override
  Future<void> elevate() async {
    try {
      await _ensureCore(elevated: true);
    } on ElevationCancelled {
      throw PermissionDeniedException();
    }
  }

  @override
  Future<List<PingResult>> realPing(
    Map<String, dynamic> probeConfig,
    List<String> tags, {
    String url = 'https://www.gstatic.com/generate_204',
    int timeoutMs = 5000,
    int attempts = 2,
  }) async {
    final out = await _request('POST', '/v1/ping/real', {
      'config': probeConfig,
      'tags': tags,
      'url': url,
      'timeoutMs': timeoutMs,
      'attempts': attempts,
    }).timeout(Duration(milliseconds: timeoutMs * attempts * tags.length + 10000));
    return [
      for (final r in out as List) PingResult.fromJson(Map<String, dynamic>.from(r as Map))
    ];
  }

  @override
  Future<List<PingResult>> tcpPing(List<({String host, int port})> targets,
      {int timeoutMs = 3000, int attempts = 2}) async {
    final out = await _request('POST', '/v1/ping/tcp', {
      'targets': [
        for (final t in targets) {'host': t.host, 'port': t.port}
      ],
      'timeoutMs': timeoutMs,
      'attempts': attempts,
    }).timeout(Duration(milliseconds: timeoutMs * attempts * targets.length + 10000));
    return [
      for (final r in out as List) PingResult.fromJson(Map<String, dynamic>.from(r as Map))
    ];
  }

  @override
  Future<void> cancelPing() async {
    if (_core == null) return;
    await _request('POST', '/v1/ping/cancel').catchError((_) => null);
  }

  @override
  Future<List<LogLine>> logs(int sinceId) async {
    if (_core == null) return const [];
    final out = await _request('GET', '/v1/logs?since=$sinceId');
    if (out is! List) return const [];
    return [
      for (final l in out) LogLine.fromJson(Map<String, dynamic>.from(l as Map))
    ];
  }

  @override
  Future<void> setLogLevel(String level) async {
    _logLevel = level;
    if (_core == null) return;
    await _request('POST', '/v1/loglevel', {'level': level});
  }

  @override
  Future<String?> validate(Map<String, dynamic> config) async {
    try {
      await _request('POST', '/v1/validate', {'config': config});
      return null;
    } on CoreError catch (e) {
      return e.message;
    }
  }

  @override
  Future<String> version() async {
    final s = await _request('GET', '/v1/status') as Map;
    return s['xray']?.toString() ?? '';
  }

  @override
  Future<void> dispose() async {
    _poll?.cancel();
    final core = _core;
    if (core != null) {
      try {
        await _call(core, 'POST', '/v1/shutdown');
      } catch (_) {}
    }
    _http.close(force: true);
    await _status.close();
  }
}

class CoreError implements Exception {
  CoreError(this.message);
  final String message;
  @override
  String toString() => message;
}
