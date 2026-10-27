import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'services/storage.dart';
import 'state/app_state.dart';
import 'ui/strings.dart';

/// Only one Tek runs at a time: the first one listens on this port, a
/// second launch hands it its arguments (for example a tek:// link) and
/// quits.
const _instancePort = 47613;

/// Returns false when another Tek is already running; [args] were passed
/// to it.
Future<bool> claimSingleInstance(List<String> args, void Function(List<String>) onMessage) async {
  try {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, _instancePort);
    server.listen((socket) {
      utf8.decoder.bind(socket).join().then((text) {
        try {
          onMessage([for (final a in jsonDecode(text) as List) a.toString()]);
        } catch (_) {}
      });
    });
    return true;
  } on SocketException {
    try {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, _instancePort,
          timeout: const Duration(seconds: 2));
      socket.write(jsonEncode(args));
      await socket.flush();
      await socket.close();
      return false;
    } catch (_) {
      // Something else took the port; run anyway.
      return true;
    }
  }
}

/// The window and the tray icon on Windows and macOS. Closing the window
/// keeps Tek (and the VPN) running in the tray.
class DesktopShell with WindowListener, TrayListener {
  DesktopShell(this.app, this.storage, this.navigatorKey);

  final AppState app;
  final Storage storage;
  final GlobalKey<NavigatorState> navigatorKey;
  bool _quitting = false;

  Future<void> init() async {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(420, 760),
      minimumSize: Size(360, 600),
      center: true,
      title: 'Tek',
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    await trayManager.setIcon(
      Platform.isWindows ? 'assets/tray/tray.ico' : 'assets/tray/tray_template.png',
      isTemplate: Platform.isMacOS,
    );
    await trayManager.setToolTip('Tek');
    trayManager.addListener(this);
    app.addListener(_updateMenu);
    await _updateMenu();
  }

  ConnState? _menuState;

  Future<void> _updateMenu() async {
    if (_menuState == app.conn) return;
    _menuState = app.conn;
    final s = S.current;
    final on = app.conn == ConnState.connected || app.conn == ConnState.connecting;
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: s.trayOpen),
      MenuItem.separator(),
      MenuItem(
        key: 'toggle',
        label: on ? s.trayDisconnect : s.trayConnect,
        disabled: !app.hasSubscription,
      ),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: s.trayQuit),
    ]));
    await trayManager.setToolTip(
        app.conn == ConnState.connected ? 'Tek · ${s.connected}' : 'Tek · ${s.disconnected}');
  }

  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    try {
      if (app.conn != ConnState.disconnected) await app.disconnect();
      await app.engine.dispose();
    } finally {
      await trayManager.destroy();
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
      exit(0);
    }
  }

  @override
  void onWindowClose() async {
    if (_quitting) return;
    final context = navigatorKey.currentContext;
    if (!storage.trayHintShown && context != null) {
      // Once: say that the VPN keeps working after the window is closed.
      await storage.setTrayHintShown();
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            content: Text(S.current.hiddenToTray),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: Text(S.current.ok)),
            ],
          ),
        );
      }
    }
    await windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() => showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        showWindow();
      case 'toggle':
        app.toggle();
      case 'quit':
        unawaited(quit());
    }
  }
}
