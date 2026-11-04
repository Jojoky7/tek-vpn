import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/android_engine.dart';
import '../core/desktop_engine.dart';
import '../services/desktop_apps.dart';
import '../state/app_state.dart';
import '../xray/config_builder.dart';
import 'app_scope.dart';
import 'strings.dart';
import 'widgets.dart';

/// Which apps go through the VPN: on Android the VPN service leaves the
/// others out, on a computer Xray sends them straight out by program.
class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key});

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _Item {
  const _Item(this.rule, this.name, this.detail, [this.icon]);
  final String rule;
  final String name;
  final String? detail;
  final Uint8List? icon;
}

class _AppsScreenState extends State<AppsScreen> {
  List<_Item>? _apps;
  late final AppState _app;
  late String _mode;
  late Set<String> _selected;
  String _query = '';

  bool get _android => _app.isAndroid;

  @override
  void initState() {
    super.initState();
    _app = AppScope.read(context);
    final st = _app.settings;
    _mode = st.perAppMode;
    _selected = {...st.perAppPackages};
    _load();
  }

  Future<void> _load() async {
    final engine = _app.engine;
    List<_Item> items = const [];
    try {
      if (engine is AndroidEngine) {
        items = [
          for (final a in await engine.installedApps()) _Item(a.package, a.label, a.package, a.icon)
        ];
      } else if (Platform.isMacOS) {
        items = [for (final a in await macApps()) _Item(a.rule, a.name, a.detail)];
      } else if (engine is DesktopEngine) {
        items = [for (final a in await engine.runningApps()) _Item(a.rule, a.name, a.detail)];
      }
    } catch (_) {}
    if (mounted) setState(() => _apps = items);
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

  Future<void> _addByName() async {
    final s = S.current;
    final mac = Platform.isMacOS;
    final text = TextEditingController();
    String? error;
    final rule = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setDialog) {
        void submit() {
          final r = appRule(text.text, mac: mac);
          if (r == null) {
            setDialog(() => error = s.badApp);
            return;
          }
          Navigator.pop(c, r);
        }

        return AlertDialog(
          title: Text(s.addApp),
          content: TextField(
            controller: text,
            autofocus: true,
            autocorrect: false,
            decoration: InputDecoration(
                hintText: mac ? s.appNameHintMac : s.appNameHintWindows, errorText: error),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text(s.cancel)),
            TextButton(onPressed: submit, child: Text(s.add)),
          ],
        );
      }),
    );
    text.dispose();
    if (rule != null) setState(() => _selected.add(rule));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final apps = _apps;
    final q = _query.toLowerCase();
    final known = {for (final a in apps ?? const <_Item>[]) a.rule};
    // Programs chosen earlier or typed in, which the list does not show now.
    final extra = [
      for (final r in _selected)
        if (!known.contains(r)) _Item(r, appLabel(r), r)
    ];
    final shown = apps == null
        ? const <_Item>[]
        : ([...apps, ...extra]
            .where((a) =>
                q.isEmpty ||
                a.name.toLowerCase().contains(q) ||
                (a.detail?.toLowerCase().contains(q) ?? false))
            .toList()
          ..sort((a, b) {
            final sa = _selected.contains(a.rule), sb = _selected.contains(b.rule);
            if (sa != sb) return sa ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }));
    final notes = [
      if (_mode == 'only') s.appsHintOnly,
      if (_mode == 'except') s.appsHintExcept,
      if (!_android && _app.settings.desktopMode == TunnelMode.proxy) s.appsProxyNote,
      if (Platform.isMacOS) s.appsMacNote,
      if (Platform.isWindows) s.appsRunningHint,
    ];
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
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(n, style: TextStyle(color: muted, fontSize: 13, height: 1.3)),
              ),
            ),
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
            child: Row(children: [
              Expanded(child: Text(s.selectedCount(_selected.length), style: TextStyle(color: muted))),
              if (!_android)
                TextButton.icon(
                  icon: const Icon(Icons.add_rounded),
                  label: Text(s.addApp),
                  onPressed: _addByName,
                ),
            ]),
          ),
          Expanded(
            child: apps == null
                ? const Center(child: CircularProgressIndicator())
                : shown.isEmpty
                    ? Center(child: Text(s.nothingFound, style: TextStyle(color: muted)))
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (_, i) {
                          final a = shown[i];
                          return CheckboxListTile(
                            value: _selected.contains(a.rule),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selected.add(a.rule);
                              } else {
                                _selected.remove(a.rule);
                              }
                            }),
                            secondary: a.icon != null
                                ? Image.memory(a.icon!, width: 36, height: 36, gaplessPlayback: true)
                                : _android
                                    ? const Icon(Icons.android_rounded, size: 36)
                                    : LetterIcon(a.name),
                            title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: a.detail == null
                                ? null
                                : Text(a.detail!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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
                child: Text(s.appsAll, textAlign: TextAlign.center, style: TextStyle(color: muted)),
              ),
            ),
          ),
      ]),
    );
  }
}
