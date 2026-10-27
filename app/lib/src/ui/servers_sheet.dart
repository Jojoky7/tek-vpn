import 'package:flutter/material.dart';

import '../model/server.dart';
import '../state/app_state.dart';
import 'app_scope.dart';
import 'strings.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> showServersSheet(BuildContext context) {
  final app = AppScope.read(context);
  if (!app.checkingAll) {
    final stale = app.servers.any((s) {
      final at = app.checks[s.id]?.at;
      return at == null || DateTime.now().difference(at) > const Duration(minutes: 2);
    });
    if (stale) app.checkServers();
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => AppScope(state: app, child: const _ServersSheet()),
  );
}

class _ServersSheet extends StatelessWidget {
  const _ServersSheet();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = S.current;
    final theme = Theme.of(context);
    final height = MediaQuery.of(context).size.height;
    return SizedBox(
      height: (height * 0.75).clamp(320, 720),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
          child: Row(children: [
            Expanded(
              child: Text(s.servers,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            ),
            TextButton.icon(
              onPressed: app.checkingAll ? null : app.checkServers,
              icon: app.checkingAll
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded, size: 20),
              label: Text(app.checkingAll ? s.checking : s.check),
            ),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            children: [
              _Row(
                leading: const FastestIcon(size: 36),
                title: s.fastest,
                subtitle: _fastestSubtitle(app),
                selected: app.selectedId == null,
                onTap: () => _pick(context, null),
              ),
              const SizedBox(height: 4),
              for (final server in app.servers)
                _Row(
                  leading: Flag(server.countryCode, size: 36),
                  title: server.name,
                  selected: app.selectedId == server.id,
                  trailing: _PingTrailing(app: app, server: server),
                  onTap: () => _pick(context, server.id),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  static String? _fastestSubtitle(AppState app) {
    final best = app.bestServer();
    if (best == null) return null;
    return app.checks[best.id]?.alive == true ? best.name : S.current.fastestHint;
  }

  void _pick(BuildContext context, String? id) {
    final app = AppScope.read(context);
    Navigator.of(context).pop();
    app.select(id);
    if (app.conn == ConnState.disconnected) app.connect();
  }
}

class _PingTrailing extends StatelessWidget {
  const _PingTrailing({required this.app, required this.server});
  final AppState app;
  final ServerNode server;

  @override
  Widget build(BuildContext context) {
    final check = app.checks[server.id];
    return Row(mainAxisSize: MainAxisSize.min, children: [
      PingDot(alive: check?.alive, checking: app.checking.contains(server.id)),
      const SizedBox(width: 8),
      SizedBox(
        width: 56,
        child: Text(pingText(check),
            textAlign: TextAlign.right,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ),
    ]);
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.leading,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final bool selected;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? TekColors.green.withValues(alpha: 0.10) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (subtitle != null)
                  Text(subtitle!,
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ]),
            ),
            ?trailing,
            if (selected) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_rounded, color: TekColors.green, size: 20),
            ] else
              const SizedBox(width: 28),
          ]),
        ),
      ),
    );
  }
}
