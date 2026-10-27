import 'package:flutter/material.dart';

import '../core/android_engine.dart';
import '../state/app_state.dart';
import 'app_scope.dart';
import 'strings.dart';

/// Android: which apps go through the VPN.
class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key});

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  List<InstalledApp>? _apps;
  late final AppState _app;
  late String _mode;
  late Set<String> _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _app = AppScope.read(context);
    final st = _app.settings;
    _mode = st.perAppMode;
    _selected = {...st.perAppPackages};
    final engine = _app.engine;
    if (engine is AndroidEngine) {
      engine.installedApps().then((a) {
        if (mounted) setState(() => _apps = a);
      });
    }
  }

  @override
  void dispose() {
    final app = _app;
    final packages = _selected.toList()..sort();
    if (_mode != app.settings.perAppMode ||
        packages.join(',') != ([...app.settings.perAppPackages]..sort()).join(',')) {
      app.updateSettings(app.settings.copyWith(perAppMode: _mode, perAppPackages: packages));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    final apps = _apps;
    final q = _query.toLowerCase();
    final shown = apps == null
        ? const <InstalledApp>[]
        : (apps.where((a) =>
                q.isEmpty || a.label.toLowerCase().contains(q) || a.package.contains(q))
            .toList()
          ..sort((a, b) {
            final sa = _selected.contains(a.package), sb = _selected.contains(b.package);
            if (sa != sb) return sa ? -1 : 1;
            return a.label.toLowerCase().compareTo(b.label.toLowerCase());
          }));
    return Scaffold(
      appBar: AppBar(title: Text(s.apps)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'off', label: Text(s.appsAllShort)),
              ButtonSegment(value: 'only', label: Text(s.appsOnly)),
              ButtonSegment(value: 'except', label: Text(s.appsExcept)),
            ],
            selected: {_mode},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _mode = v.first),
          ),
        ),
        if (_mode != 'off') ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: s.search,
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(s.selectedCount(_selected.length),
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ),
          Expanded(
            child: apps == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (_, i) {
                      final a = shown[i];
                      return CheckboxListTile(
                        value: _selected.contains(a.package),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(a.package);
                          } else {
                            _selected.remove(a.package);
                          }
                        }),
                        secondary: a.icon == null
                            ? const Icon(Icons.android_rounded, size: 36)
                            : Image.memory(a.icon!, width: 36, height: 36, gaplessPlayback: true),
                        title: Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(a.package,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12)),
                      );
                    },
                  ),
          ),
        ] else
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(s.appsAll,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            ),
          ),
      ]),
    );
  }
}
