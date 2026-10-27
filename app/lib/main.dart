import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'src/core/android_engine.dart';
import 'src/core/desktop_engine.dart';
import 'src/core/engine.dart';
import 'src/desktop.dart';
import 'src/services/storage.dart';
import 'src/services/subscription_service.dart';
import 'src/services/tek_api.dart';
import 'src/state/app_state.dart';
import 'src/ui/app_scope.dart';
import 'src/ui/home_screen.dart';
import 'src/ui/strings.dart';
import 'src/ui/theme.dart';

final _navigator = GlobalKey<NavigatorState>();
final _messenger = GlobalKey<ScaffoldMessengerState>();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final desktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  final pendingLinks = <String>[..._linksIn(args)];
  AppState? state;
  if (desktop) {
    final first = await claimSingleInstance(args, (more) async {
      final links = _linksIn(more);
      if (state != null) {
        await windowShell?.showWindow();
        for (final l in links) {
          await _importLink(state!, l);
        }
      }
    });
    if (!first) exit(0);
  }

  final storage = await Storage.open();
  S.use(storage.settings.language);
  final support = await getApplicationSupportDirectory();
  final assetDir = await _installGeoFiles(support.path);
  final TekEngine engine = Platform.isAndroid
      ? AndroidEngine()
      : DesktopEngine('${support.path}${Platform.pathSeparator}core');
  await engine.init(assetDir);
  final info = await PackageInfo.fromPlatform();

  final app = AppState(
    engine: engine,
    storage: storage,
    subscriptions: SubscriptionService(info.version),
    api: TekApi(),
    isAndroid: Platform.isAndroid,
  );
  state = app;
  await app.init();

  if (desktop) {
    windowShell = DesktopShell(app, storage, _navigator);
    await windowShell!.init();
  }

  runApp(TekApp(state: app));

  // tek://add/<link> from the site's "open in app" button.
  try {
    final links = AppLinks();
    final initial = await links.getInitialLink();
    if (initial != null) pendingLinks.add(initial.toString());
    links.uriLinkStream.listen((uri) => _importLink(app, uri.toString()));
  } catch (_) {}
  for (final l in pendingLinks.toSet()) {
    await _importLink(app, l);
  }
}

DesktopShell? windowShell;

List<String> _linksIn(List<String> args) => [
      for (final a in args)
        if (a.toLowerCase().startsWith('tek://') || a.toLowerCase().startsWith('happ://add/')) a
    ];

Future<void> _importLink(AppState app, String link) async {
  if (SubscriptionService.normalizeUrl(link) == null) return;
  final ok = await app.addSubscription(link);
  if (ok) {
    _messenger.currentState?.showSnackBar(SnackBar(content: Text(S.current.subscriptionAdded)));
  }
}

/// Copies geoip.dat and geosite.dat out of the app bundle, where Xray can
/// read them, when they are missing or the app brought new ones.
Future<String> _installGeoFiles(String supportDir) async {
  final dir = Directory('$supportDir${Platform.pathSeparator}geo');
  await dir.create(recursive: true);
  for (final name in const ['geoip.dat', 'geosite.dat']) {
    final data = await rootBundle.load('assets/geo/$name');
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    if (!file.existsSync() || file.lengthSync() != data.lengthInBytes) {
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true);
      await tmp.rename(file.path);
    }
  }
  return dir.path;
}

class TekApp extends StatelessWidget {
  const TekApp({super.key, required this.state, this.home = const HomeScreen()});
  final AppState state;
  final Widget home;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Tek',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navigator,
        scaffoldMessengerKey: _messenger,
        theme: tekTheme(Brightness.light),
        darkTheme: tekTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: home,
      ),
    );
  }
}
