import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/engine.dart';
import '../model/server.dart';
import '../model/subscription.dart';
import '../services/settings.dart';
import '../services/storage.dart';
import '../services/subscription_service.dart';
import '../services/tek_api.dart';
import '../xray/config_builder.dart';

enum ConnState { disconnected, connecting, connected, disconnecting }

/// Something went wrong; [key] picks the text in the UI, [detail] is the
/// technical part for the log.
class AppError {
  const AppError(this.key, [this.detail]);
  final String key;
  final String? detail;
}

/// Everything the screens show and every action they can take.
class AppState extends ChangeNotifier {
  AppState({
    required this.engine,
    required this.storage,
    required this.subscriptions,
    required this.api,
    required this.isAndroid,
  });

  final TekEngine engine;
  final Storage storage;
  final SubscriptionService subscriptions;
  final TekApi api;
  final bool isAndroid;

  Subscription? subscription;
  Settings settings = const Settings();

  /// The chosen server id; null means "fastest".
  String? selectedId;

  final Map<String, CheckResult> checks = {};
  final Set<String> checking = {};
  bool checkingAll = false;
  bool refreshing = false;

  ConnState conn = ConnState.disconnected;
  DateTime? connectedSince;
  String? connectedServerId;

  /// The server in use stopped answering.
  bool serverTrouble = false;

  /// Bytes per second through the VPN.
  int speedDown = 0;
  int speedUp = 0;

  AppError? error;

  /// The tekvpn.com account, if the user signed in.
  String? accountEmail;

  ApiProxy? _api;
  StreamSubscription<EngineStatus>? _statusSub;
  Timer? _healthTimer;
  Timer? _refreshTimer;
  int _lastUp = 0, _lastDown = 0;
  DateTime? _lastTraffic;
  int _healthFailures = 0;
  bool _connectBusy = false;

  List<ServerNode> get servers => subscription?.servers ?? const [];

  bool get hasSubscription => subscription != null && servers.isNotEmpty;

  /// The server in use, or the one the button would connect to.
  ServerNode? get currentServer {
    if (conn != ConnState.disconnected && connectedServerId != null) {
      final s = _byId(connectedServerId!);
      if (s != null) return s;
    }
    if (selectedId != null) {
      final s = _byId(selectedId!);
      if (s != null) return s;
    }
    return bestServer();
  }

  ServerNode? _byId(String id) {
    for (final s in servers) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// The fastest working server; the first one when nothing is known yet.
  ServerNode? bestServer({Set<String> exclude = const {}}) {
    final pool = servers.where((s) => !exclude.contains(s.id)).toList();
    if (pool.isEmpty) return null;
    final alive = pool.where((s) => checks[s.id]?.alive == true).toList()
      ..sort((a, b) => _delay(a).compareTo(_delay(b)));
    if (alive.isNotEmpty) return alive.first;
    final unknown = pool.where((s) => checks[s.id]?.alive == null);
    return unknown.isNotEmpty ? unknown.first : pool.first;
  }

  int _delay(ServerNode s) {
    final c = checks[s.id];
    return c?.tcpMs ?? c?.realMs ?? 99999;
  }

  // --- start -------------------------------------------------------------

  Future<void> init() async {
    subscription = storage.subscription;
    settings = storage.settings;
    selectedId = storage.selectedServer;
    checks.addAll(storage.checks);
    accountEmail = storage.account?['email'];
    await engine.setLogLevel(settings.verboseLog ? 'debug' : 'warning').catchError((_) {});

    _statusSub = engine.status.listen(_onStatus);
    _onStatus(engine.current);

    // Refresh the subscription when it is older than it asks for.
    final sub = subscription;
    if (sub != null) {
      final hours = sub.info.updateIntervalHours ?? 12;
      if (DateTime.now().difference(sub.updatedAt) > Duration(hours: hours)) {
        unawaited(refreshSubscription(silent: true));
      } else {
        unawaited(_checkIfStale());
      }
    }
    _refreshTimer = Timer.periodic(const Duration(hours: 1), (_) {
      final s = subscription;
      if (s == null) return;
      final hours = s.info.updateIntervalHours ?? 12;
      if (DateTime.now().difference(s.updatedAt) > Duration(hours: hours)) {
        unawaited(refreshSubscription(silent: true));
      }
    });
  }

  Future<void> _checkIfStale() async {
    final times = [for (final s in servers) checks[s.id]?.at];
    final stale = times.any(
        (t) => t == null || DateTime.now().difference(t) > const Duration(minutes: 5));
    if (stale) await checkServers();
  }

  void _onStatus(EngineStatus s) {
    final before = conn;
    switch (s.state) {
      case CoreState.running:
        if (_connectBusy) break; // connect() decides when it is done
        conn = ConnState.connected;
        connectedSince = s.since ?? connectedSince ?? DateTime.now();
        if (connectedServerId == null && s.serverId != null) {
          connectedServerId = s.serverId;
        }
        _updateSpeed(s);
      case CoreState.starting:
        conn = ConnState.connecting;
      case CoreState.stopping:
        if (_connectBusy) break;
        conn = ConnState.disconnecting;
      case CoreState.stopped:
        if (_connectBusy && conn == ConnState.connecting) break;
        conn = ConnState.disconnected;
        connectedSince = null;
        speedDown = speedUp = 0;
        _lastTraffic = null;
        if (s.error != null && before != ConnState.disconnected) {
          error = AppError('connectionLost', s.error);
        }
    }
    if (conn == ConnState.connected && before != ConnState.connected) {
      _startHealth();
    } else if (conn == ConnState.disconnected) {
      _healthTimer?.cancel();
      serverTrouble = false;
    }
    notifyListeners();
  }

  void _updateSpeed(EngineStatus s) {
    final now = DateTime.now();
    final last = _lastTraffic;
    if (last != null) {
      final ms = now.difference(last).inMilliseconds;
      if (ms > 200) {
        speedUp = max(0, ((s.up - _lastUp) * 1000 / ms).round());
        speedDown = max(0, ((s.down - _lastDown) * 1000 / ms).round());
      }
    }
    _lastUp = s.up;
    _lastDown = s.down;
    _lastTraffic = now;
  }

  // --- subscription ----------------------------------------------------

  /// Adds a subscription from a link, a QR code or an import link.
  Future<bool> addSubscription(String input) async {
    final url = SubscriptionService.normalizeUrl(input);
    if (url == null) {
      error = const AppError('badLink');
      notifyListeners();
      return false;
    }
    refreshing = true;
    error = null;
    notifyListeners();
    try {
      final sub = await subscriptions.fetch(url, via: _api);
      final first = subscription == null;
      subscription = sub;
      await storage.setSubscription(sub);
      if (first || _byId(selectedId ?? '') == null) {
        selectedId = null;
        await storage.setSelectedServer(null);
      }
      _dropOldChecks();
      unawaited(checkServers());
      return true;
    } on SubscriptionException catch (e) {
      error = AppError('sub_${e.kind}', e.detail);
      return false;
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  Future<void> refreshSubscription({bool silent = false}) async {
    final sub = subscription;
    if (sub == null || refreshing) return;
    refreshing = true;
    if (!silent) error = null;
    notifyListeners();
    try {
      final fresh = await subscriptions.fetch(sub.url, via: _api);
      subscription = fresh;
      await storage.setSubscription(fresh);
      if (selectedId != null && _byId(selectedId!) == null) {
        selectedId = null;
        await storage.setSelectedServer(null);
      }
      _dropOldChecks();
      unawaited(checkServers());
    } on SubscriptionException catch (e) {
      if (!silent || e.kind == 'notFound') error = AppError('sub_${e.kind}', e.detail);
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  Future<void> removeSubscription() async {
    if (conn != ConnState.disconnected) await disconnect();
    subscription = null;
    selectedId = null;
    checks.clear();
    await storage.setSubscription(null);
    await storage.setSelectedServer(null);
    await storage.setChecks({});
    notifyListeners();
  }

  void _dropOldChecks() {
    final ids = {for (final s in servers) s.id};
    checks.removeWhere((id, _) => !ids.contains(id));
  }

  // --- account -----------------------------------------------------------

  /// Signs in to tekvpn.com (or creates the account) and adds its
  /// subscription.
  Future<bool> signIn(String email, String password, {required bool register}) async {
    error = null;
    if (register && !TekApi.isGmail(email)) {
      error = const AppError('gmailOnly');
      notifyListeners();
      return false;
    }
    if (password.length < 8) {
      error = const AppError('shortPassword');
      notifyListeners();
      return false;
    }
    refreshing = true;
    notifyListeners();
    try {
      final token = register
          ? await api.register(email, password, via: _api)
          : await api.login(email, password, via: _api);
      await storage.setAccount({'email': email.trim(), 'token': token});
      accountEmail = email.trim();
      var keys = await api.keys(token, via: _api);
      if (keys.isEmpty && register) {
        // The site gives new accounts a trial the same way.
        try {
          await api.trial(token, via: _api);
          keys = await api.keys(token, via: _api);
        } on TekApiException catch (_) {}
      }
      if (keys.isEmpty) {
        error = const AppError('noKeys');
        return false;
      }
      final key = keys.firstWhere((k) => k.active, orElse: () => keys.first);
      refreshing = false;
      return await addSubscription(key.subscriptionUrl);
    } on TekApiException catch (e) {
      error = switch (e.code) {
        'email_taken' => const AppError('emailTaken'),
        'network' => AppError('sub_network', e.message),
        _ => AppError('signInFailed', e.message),
      };
      return false;
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await storage.setAccount(null);
    accountEmail = null;
    notifyListeners();
  }

  // --- servers ---------------------------------------------------------

  Future<void> select(String? id) async {
    selectedId = id;
    await storage.setSelectedServer(id);
    notifyListeners();
    if (conn == ConnState.connected) {
      final target = currentServerFor(id);
      if (target != null && target.id != connectedServerId) await connect();
    }
  }

  ServerNode? currentServerFor(String? id) => id == null ? bestServer() : _byId(id);

  ConnectOptions _options() => ConnectOptions(
        mode: isAndroid ? TunnelMode.tun : settings.desktopMode,
        ruDirect: settings.ruDirect,
        fragmentation: settings.fragmentation,
        blockQuic: settings.blockQuic,
        logLevel: settings.verboseLog ? 'debug' : 'warning',
      );

  XrayConfigBuilder _builder() => XrayConfigBuilder(servers,
      subscriptionFragment: subscription?.info.fragment);

  /// Checks every server: the TCP time first (the number in the list), then
  /// a real request through each server, one at a time (the dot).
  Future<void> checkServers() async {
    if (checkingAll || servers.isEmpty) return;
    checkingAll = true;
    final list = List<ServerNode>.of(servers);
    checking.addAll(list.map((s) => s.id));
    notifyListeners();
    final builder = _builder();
    final probe = builder.probe(_options());
    try {
      final tcp = await engine.tcpPing([for (final s in list) (host: s.host, port: s.port)]);
      for (var i = 0; i < list.length && i < tcp.length; i++) {
        final old = checks[list[i].id];
        checks[list[i].id] = CheckResult(
          alive: old?.alive,
          tcpMs: tcp[i].ok ? tcp[i].ms : null,
          realMs: old?.realMs,
          at: old?.at,
        );
      }
      notifyListeners();
      for (final s in list) {
        if (!servers.any((x) => x.id == s.id)) continue;
        final r = await engine.realPing(probe, [builder.tagOf(s)]);
        if (r.isEmpty || r.first.error == 'cancelled') break;
        final ok = r.first.ok;
        final old = checks[s.id];
        checks[s.id] = CheckResult(
          alive: ok,
          tcpMs: old?.tcpMs,
          realMs: ok ? r.first.ms : null,
          at: DateTime.now(),
        );
        checking.remove(s.id);
        notifyListeners();
      }
      await storage.setChecks(checks);
    } catch (e) {
      debugPrint('check failed: $e');
    } finally {
      checking.clear();
      checkingAll = false;
      notifyListeners();
    }
  }

  // --- connection ------------------------------------------------------

  Future<void> toggle() async {
    if (conn == ConnState.connected || conn == ConnState.connecting) {
      await disconnect();
    } else if (conn == ConnState.disconnected) {
      await connect();
    }
  }

  Future<void> connect({ServerNode? server}) async {
    if (!hasSubscription) {
      error = const AppError('noSubscription');
      notifyListeners();
      return;
    }
    final target = server ?? currentServerFor(selectedId) ?? servers.first;
    _connectBusy = true;
    error = null;
    serverTrouble = false;
    conn = ConnState.connecting;
    connectedServerId = target.id;
    notifyListeners();
    try {
      await engine.cancelPing();
      _api = await _newApiProxy();
      final options = _options();
      final config = _builder().connection(target, options, api: _api);
      try {
        await _start(config, options, target);
      } on NeedsAdminException {
        // "All traffic" on a computer: ask for administrator rights once.
        await engine.elevate();
        await _start(config, options, target);
      }
      final s = await _waitStarted();
      if (!s.running) throw StateError(s.error ?? 'the VPN did not start');
      conn = ConnState.connected;
      connectedSince = s.since ?? DateTime.now();
      _lastTraffic = null;
      _startHealth();
      if (checks.values.any((c) => c.at == null) ||
          servers.any((x) => checks[x.id]?.at == null)) {
        unawaited(checkServers());
      }
    } on PermissionDeniedException {
      conn = ConnState.disconnected;
      error = AppError(isAndroid ? 'vpnDenied' : 'adminDenied');
    } catch (e) {
      conn = ConnState.disconnected;
      error = AppError('connectFailed', '$e');
    } finally {
      _connectBusy = false;
      notifyListeners();
    }
  }

  Future<void> _start(Map<String, dynamic> config, ConnectOptions options, ServerNode target) =>
      engine.start(
        config,
        mode: options.mode,
        options: options,
        android: AndroidVpnOptions(
          perAppMode: settings.perAppMode,
          packages: settings.perAppPackages,
        ),
        serverName: target.name,
        serverId: target.id,
      );

  /// Android brings the VPN up after start() returns; wait for the outcome.
  Future<EngineStatus> _waitStarted() async {
    final now = engine.current;
    if (now.state == CoreState.running || now.state == CoreState.stopped) return now;
    try {
      return await engine.status
          .firstWhere((s) => s.state == CoreState.running || s.state == CoreState.stopped)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      return EngineStatus(CoreState.stopped, error: 'timeout');
    }
  }

  Future<void> disconnect() async {
    _healthTimer?.cancel();
    conn = ConnState.disconnecting;
    notifyListeners();
    try {
      await engine.stop();
    } catch (e) {
      debugPrint('stop failed: $e');
    }
    conn = ConnState.disconnected;
    connectedSince = null;
    _api = null;
    notifyListeners();
  }

  static Future<ApiProxy> _newApiProxy() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    final rnd = Random.secure();
    String word() => List.generate(16, (_) => rnd.nextInt(36).toRadixString(36)).join();
    return ApiProxy(port, word(), word());
  }

  /// While connected, checks the server in use every minute. When it stops
  /// answering and "fastest" is on, Tek moves to the next working server.
  void _startHealth() {
    _healthTimer?.cancel();
    _healthFailures = 0;
    _healthTimer = Timer.periodic(const Duration(seconds: 60), (_) => _health());
  }

  Future<void> _health() async {
    if (conn != ConnState.connected || checkingAll) return;
    try {
      final r = await engine.realPing(const {}, const [XrayConfigBuilder.proxyTag],
          attempts: 2);
      if (r.isNotEmpty && r.first.ok) {
        _healthFailures = 0;
        if (serverTrouble) {
          serverTrouble = false;
          notifyListeners();
        }
        return;
      }
    } catch (_) {
      return;
    }
    _healthFailures++;
    if (_healthFailures < 2) return;
    final current = connectedServerId;
    if (current != null) {
      final old = checks[current];
      checks[current] = CheckResult(alive: false, tcpMs: old?.tcpMs, at: DateTime.now());
    }
    if (selectedId == null && servers.length > 1) {
      final next = bestServer(exclude: {?current});
      if (next != null && checks[next.id]?.alive != false) {
        await connect(server: next);
        return;
      }
    }
    serverTrouble = true;
    notifyListeners();
  }

  // --- settings --------------------------------------------------------

  Future<void> updateSettings(Settings s) async {
    final old = settings;
    settings = s;
    await storage.setSettings(s);
    if (old.verboseLog != s.verboseLog) {
      await engine.setLogLevel(s.verboseLog ? 'debug' : 'warning').catchError((_) {});
    }
    notifyListeners();
    final needsReconnect = old.ruDirect != s.ruDirect ||
        old.fragmentation != s.fragmentation ||
        old.blockQuic != s.blockQuic ||
        old.desktopMode != s.desktopMode ||
        old.perAppMode != s.perAppMode ||
        !listEquals(old.perAppPackages, s.perAppPackages) ||
        old.verboseLog != s.verboseLog;
    if (needsReconnect && conn == ConnState.connected) {
      final server = connectedServerId == null ? null : _byId(connectedServerId!);
      await connect(server: server);
    }
  }

  void clearError() {
    if (error == null) return;
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _healthTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }
}
