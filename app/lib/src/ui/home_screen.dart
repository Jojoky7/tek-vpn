import 'dart:async';

import 'package:flutter/material.dart';

import '../model/subscription.dart';
import '../state/app_state.dart';
import 'add_subscription_screen.dart';
import 'app_scope.dart';
import 'servers_sheet.dart';
import 'settings_screen.dart';
import 'strings.dart';
import 'theme.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _clock;
  AppError? _shownError;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && AppScope.read(context).conn == ConnState.connected) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _showError(AppState app) {
    final e = app.error;
    if (e == null || identical(e, _shownError)) return;
    // Screens on top show their own errors.
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _shownError = e;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(S.current.error(e.key))));
      app.clearError();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = S.current;
    _showError(app);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Row(mainAxisSize: MainAxisSize.min, children: [
          TekMark(size: 26),
          SizedBox(width: 8),
          Text('Tek', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
        ]),
        actions: [
          IconButton(
            tooltip: s.settings,
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final compact = box.maxHeight < 600;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox(height: compact ? 8 : 32),
                  _Status(app: app, buttonSize: compact ? 140 : 176),
                  SizedBox(height: compact ? 16 : 32),
                  Column(children: [
                    if (app.hasSubscription) ...[
                      _ServerCard(app: app),
                      const SizedBox(height: 12),
                      _SubscriptionCard(info: app.subscription!.info),
                    ] else
                      FilledButton.icon(
                        icon: const Icon(Icons.add_rounded),
                        label: Text(s.addSubscription),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => const AddSubscriptionScreen())),
                      ),
                  ]),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.app, required this.buttonSize});
  final AppState app;
  final double buttonSize;

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final (label, color) = switch (app.conn) {
      ConnState.connected => (s.connected, TekColors.green),
      ConnState.connecting => (s.connecting, theme.colorScheme.onSurface),
      ConnState.disconnecting => (s.disconnecting, theme.colorScheme.onSurface),
      ConnState.disconnected => (s.disconnected, theme.colorScheme.onSurface),
    };
    final since = app.connectedSince;
    return Column(children: [
      PowerButton(
        state: app.conn,
        size: buttonSize,
        onTap: () {
          if (!app.hasSubscription) {
            Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AddSubscriptionScreen()));
            return;
          }
          app.toggle();
        },
      ),
      const SizedBox(height: 20),
      Text(label,
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w600, color: color, letterSpacing: -0.3)),
      const SizedBox(height: 6),
      SizedBox(
        height: 40,
        child: app.conn == ConnState.connected && since != null
            ? Column(children: [
                Text(_elapsed(DateTime.now().difference(since)),
                    style: TextStyle(
                        color: muted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        fontSize: 15)),
                const SizedBox(height: 2),
                Text('↓ ${s.speed(app.speedDown)}   ↑ ${s.speed(app.speedUp)}',
                    style: TextStyle(
                        color: muted,
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ])
            : app.serverTrouble
                ? Text(s.error('serverTrouble'), style: const TextStyle(color: TekColors.amber))
                : null,
      ),
    ]);
  }

  static String _elapsed(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    final theme = Theme.of(context);
    final auto = app.selectedId == null;
    final server = app.currentServer;
    final check = server == null ? null : app.checks[server.id];
    final connectedHere = app.conn == ConnState.connected;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showServersSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            if (auto && !connectedHere)
              const FastestIcon(size: 36)
            else
              Flag(server?.countryCode, size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  auto && !connectedHere ? s.fastest : (server?.name ?? ''),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  auto ? (connectedHere ? s.fastest : s.fastestHint) : s.changeServer,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
            if (server != null && !(auto && !connectedHere)) ...[
              PingDot(alive: check?.alive, checking: app.checking.contains(server.id)),
              const SizedBox(width: 6),
              Text(pingText(check),
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13)),
              const SizedBox(width: 4),
            ],
            Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.info});
  final SubscriptionInfo info;

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final expire = info.expire;

    String headline;
    Color? headlineColor;
    double? progress;
    if (info.expired) {
      headline = s.expired;
      headlineColor = TekColors.red;
    } else if (info.trafficOver) {
      headline = s.trafficOver;
      headlineColor = TekColors.red;
      progress = 1;
    } else if (info.unlimited) {
      headline = s.unlimited;
    } else {
      final total = info.total!;
      final left = (total - info.used).clamp(0, total);
      headline = s.trafficLeft(s.bytes(left), s.bytes(total));
      progress = total == 0 ? null : info.used / total;
    }
    String? sub;
    if (expire != null && !info.expired) {
      final days = expire.difference(DateTime.now()).inDays;
      sub = '${s.until(s.date(expire))} · ${s.daysLeft(days < 0 ? 0 : days)}';
    } else if (expire != null) {
      sub = s.date(expire);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(headline,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600, color: headlineColor)),
          if (progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: progress > 0.9 ? TekColors.amber : TekColors.green,
              ),
            ),
          ],
          if (sub != null) ...[
            const SizedBox(height: 8),
            Text(sub, style: TextStyle(color: muted, fontSize: 13)),
          ],
        ]),
      ),
    );
  }
}
