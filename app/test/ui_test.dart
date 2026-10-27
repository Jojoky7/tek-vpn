// Builds every screen with a stand-in engine, so a layout or state error
// fails here instead of on someone's phone. With TEK_SHOTS=<folder> set, it
// also saves a picture of each screen there.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tek/main.dart';
import 'package:tek/src/core/engine.dart';
import 'package:tek/src/model/subscription.dart';
import 'package:tek/src/parse/subscription_parser.dart';
import 'package:tek/src/services/storage.dart';
import 'package:tek/src/services/subscription_service.dart';
import 'package:tek/src/services/tek_api.dart';
import 'package:tek/src/state/app_state.dart';
import 'package:tek/src/ui/add_subscription_screen.dart';
import 'package:tek/src/ui/login_screen.dart';
import 'package:tek/src/ui/settings_screen.dart';
import 'package:tek/src/ui/strings.dart';
import 'package:tek/src/ui/widgets.dart';
import 'package:tek/src/xray/config_builder.dart';

class FakeEngine extends TekEngine {
  final _status = StreamController<EngineStatus>.broadcast();
  EngineStatus _current = EngineStatus.stopped;
  final starts = <ConnectOptions>[];

  /// Errors the next start() calls throw, as a real core would.
  final failures = <String>[];

  void _emit(EngineStatus s) {
    _current = s;
    _status.add(s);
  }

  @override
  bool get supportsModes => true;
  @override
  Stream<EngineStatus> get status => _status.stream;
  @override
  EngineStatus get current => _current;
  @override
  String get assetDir => '';
  @override
  Future<void> init(String assetDir) async {}

  @override
  Future<void> start(Map<String, dynamic> config,
      {required TunnelMode mode,
      required ConnectOptions options,
      AndroidVpnOptions android = const AndroidVpnOptions(),
      String serverName = '',
      String serverId = ''}) async {
    starts.add(options);
    if (failures.isNotEmpty) throw StateError(failures.removeAt(0));
    _emit(EngineStatus(CoreState.running,
        since: DateTime.now().subtract(const Duration(minutes: 12, seconds: 7)),
        mode: mode,
        serverId: serverId,
        up: 48 * 1024 * 1024,
        down: 734 * 1024 * 1024));
  }

  @override
  Future<void> stop() async => _emit(EngineStatus.stopped);

  @override
  Future<List<PingResult>> realPing(Map<String, dynamic> probeConfig, List<String> tags,
          {String url = '', int timeoutMs = 5000, int attempts = 2}) async =>
      [for (final _ in tags) const PingResult(180)];

  @override
  Future<List<PingResult>> tcpPing(List<({String host, int port})> targets,
          {int timeoutMs = 3000, int attempts = 2}) async =>
      [for (final _ in targets) const PingResult(42)];

  @override
  Future<void> cancelPing() async {}
  @override
  Future<List<LogLine>> logs(int sinceId) async => const [];
  @override
  Future<void> setLogLevel(String level) async {}
  @override
  Future<String?> validate(Map<String, dynamic> config) async => null;
  @override
  Future<String> version() async => '26.3.27';
  @override
  Future<void> dispose() async => _status.close();
}

const _link = 'vless://1b4e3a2c-5d6f-4a8b-9c0d-1e2f3a4b5c6d@{host}:{port}'
    '?security=reality&sni=vk.com&fp=firefox&pbk=-vOyZ_nEJ7fEFBDEFIwBXMqJ1bydkjLl6toqR9ulugs'
    '&sid=abcd1234&type=xhttp&path=/api/v1/data&mode=auto#{name}';

Subscription _subscription() {
  String link(String host, int port, String name) => _link
      .replaceFirst('{host}', host)
      .replaceFirst('{port}', '$port')
      .replaceFirst('{name}', Uri.encodeComponent(name));
  final body = [
    link('82.115.7.56', 2083, '🇳🇱 Нидерланды'),
    link('62.182.193.32', 2083, '🇸🇪 Швеция'),
    link('10.0.0.3', 2083, '🇱🇻 Латвия'),
    link('10.0.0.4', 2083, '🇬🇧 Великобритания'),
    link('82.115.7.56', 2087, '🇷🇺 Москва'),
  ].join('\n');
  final expire = DateTime.now().add(const Duration(days: 18)).millisecondsSinceEpoch ~/ 1000;
  final parsed = parseSubscription(body, headers: {
    'subscription-userinfo':
        'upload=1073741824; download=24159191040; total=107374182400; expire=$expire',
    'profile-title': 'TekVPN',
  });
  return Subscription(
    url: 'https://tekvpn.com/sub/test',
    info: parsed.info,
    servers: parsed.servers,
    updatedAt: DateTime.now(),
  );
}

Future<void> _loadFonts() async {
  final material = '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}'
      '/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final file = File('$material/$f');
      if (!file.existsSync()) return;
      loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await loader.load();
  }

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  // Text styles without a family use the tester's default font (boxes).
  await load('Ahem', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

final _shot = GlobalKey();

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<void> _save(WidgetTester tester, String name) async {
  final dir = Platform.environment['TEK_SHOTS'];
  if (dir == null) return;
  await _settle(tester);
  final boundary = _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(dir).create(recursive: true);
    await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<AppState> _app({required bool withSubscription, required bool android}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = await Storage.open();
  if (withSubscription) {
    final sub = _subscription();
    await storage.setSubscription(sub);
    final now = DateTime.now();
    await storage.setChecks({
      for (final (i, s) in sub.servers.indexed)
        s.id: i == 3
            ? CheckResult(alive: false, tcpMs: 61, at: now)
            : CheckResult(alive: true, tcpMs: [38, 44, 52, 0, 9][i], realMs: 180, at: now),
    });
  }
  final app = AppState(
    engine: FakeEngine(),
    storage: storage,
    subscriptions: SubscriptionService('1.0.0'),
    api: TekApi(),
    isAndroid: android,
  );
  await app.init();
  return app;
}

Widget _wrap(AppState app, {Widget? screen}) => RepaintBoundary(
      key: _shot,
      child: screen == null
          ? TekApp(state: app)
          : TekApp(state: app, home: screen),
    );

void main() {
  setUpAll(() async {
    PackageInfo.setMockInitialValues(
        appName: 'Tek',
        packageName: 'com.tekvpn.app',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '');
    S.use('ru');
    await _loadFonts();
  });

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';

    testWidgets('phone screens ($theme)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.platformBrightnessTestValue =
          dark ? Brightness.dark : Brightness.light;
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
        debugDefaultTargetPlatformOverride = null;
      });

      final empty = await _app(withSubscription: false, android: true);
      await tester.pumpWidget(_wrap(empty));
      await _settle(tester);
      await _save(tester, 'phone-$theme-1-first-launch');

      await tester.pumpWidget(_wrap(empty, screen: const AddSubscriptionScreen()));
      await _settle(tester);
      await _save(tester, 'phone-$theme-2-add-subscription');

      await tester.pumpWidget(_wrap(empty, screen: const LoginScreen()));
      await _settle(tester);
      await _save(tester, 'phone-$theme-3-login');
      empty.dispose();

      final app = await _app(withSubscription: true, android: true);
      await tester.pumpWidget(Container());
      await tester.pumpWidget(_wrap(app));
      await _settle(tester);
      await _save(tester, 'phone-$theme-4-home');

      // connect() opens a real socket to pick a port: run it outside the fake clock.
      await tester.runAsync(() => app.connect());
      await _settle(tester);
      expect(app.conn, ConnState.connected, reason: '${app.error?.key} ${app.error?.detail}');
      await _save(tester, 'phone-$theme-5-connected');

      // "Fastest" never lands on the Moscow exit, even with the lowest ping.
      expect(app.connectedServerId, isNot(app.servers.last.id));
      expect(app.servers.last.countryCode, 'ru');
      await tester.tap(find.byType(Flag).first);
      await _settle(tester);
      await _save(tester, 'phone-$theme-6-servers');
      await tester.tapAt(const Offset(20, 40));
      await _settle(tester);

      await tester.pumpWidget(_wrap(app, screen: const SettingsScreen()));
      await _settle(tester);
      await _save(tester, 'phone-$theme-7-settings');

      await tester.runAsync(() => app.disconnect());
      await tester.pumpWidget(Container());
      app.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('computer window', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(420 * 2, 760 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(() {
      tester.view.reset();
      debugDefaultTargetPlatformOverride = null;
    });

    final app = await _app(withSubscription: true, android: false);
    await tester.pumpWidget(_wrap(app));
    await _settle(tester);
    await tester.runAsync(() => app.connect());
    await _settle(tester);
    expect(app.conn, ConnState.connected, reason: '${app.error?.key} ${app.error?.detail}');
    await _save(tester, 'desktop-1-connected');

    await tester.pumpWidget(_wrap(app, screen: const SettingsScreen()));
    await _settle(tester);
    await _save(tester, 'desktop-2-settings');

    await tester.runAsync(() => app.disconnect());
    await tester.pumpWidget(Container());
    app.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  test('computer: proxy ports move when another app holds them', () async {
    final app = await _app(withSubscription: true, android: false);
    final engine = app.engine as FakeEngine;
    final taken = await ServerSocket.bind(InternetAddress.loopbackIPv4, 10808)
        .then<ServerSocket?>((s) => s, onError: (_) => null);
    await app.connect();
    expect(app.conn, ConnState.connected);
    if (taken != null) expect(engine.starts.last.socksPort, isNot(10808));
    await taken?.close();
    await app.disconnect();

    // The port is taken between the check and the start: one more try.
    engine.failures.add('app/proxyman/inbound: failed to listen TCP on 10808 > '
        'listen tcp 127.0.0.1:10808: bind: address already in use');
    engine.starts.clear();
    await app.connect();
    expect(app.conn, ConnState.connected);
    expect(engine.starts, hasLength(2));
    expect(engine.starts.last.socksPort, isNot(10808));
    await app.disconnect();

    // Any other failure is reported with its reason.
    engine.failures.add('cannot set the system proxy: access denied');
    await app.connect();
    expect(app.conn, ConnState.disconnected);
    expect(app.error?.key, 'connectFailed');
    expect(app.error?.detail, contains('system proxy'));
    app.dispose();
  });
}
