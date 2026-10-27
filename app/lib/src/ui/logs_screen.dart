import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/engine.dart';
import 'app_scope.dart';
import 'strings.dart';
import 'theme.dart';

/// The core's journal, to copy and send to support.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final _lines = <LogLine>[];
  final _scroll = ScrollController();
  Timer? _timer;
  int _last = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final more = await AppScope.read(context).engine.logs(_last);
      if (!mounted || more.isEmpty) return;
      final atEnd = !_scroll.hasClients ||
          _scroll.position.pixels >= _scroll.position.maxScrollExtent - 40;
      setState(() {
        _lines.addAll(more);
        _last = more.last.id;
        if (_lines.length > 3000) _lines.removeRange(0, _lines.length - 3000);
      });
      if (atEnd) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
    } catch (_) {}
  }

  String _text() => _lines
      .map((l) =>
          '${l.time.toLocal().toIso8601String().substring(11, 23)} ${l.level.toUpperCase()} ${l.text}')
      .join('\n');

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.logs),
        actions: [
          IconButton(
            tooltip: s.copy,
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: _lines.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _text()));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(s.copied)));
                  },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _lines.isEmpty
          ? Center(
              child: Text(s.emptyLog,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant)))
          : SelectionArea(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: _lines.length,
                itemBuilder: (_, i) {
                  final l = _lines[i];
                  final color = switch (l.level) {
                    'error' => TekColors.red,
                    'warning' => TekColors.amber,
                    _ => theme.colorScheme.onSurfaceVariant,
                  };
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: '${l.time.toLocal().toIso8601String().substring(11, 19)}  ',
                            style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                        TextSpan(text: l.text, style: TextStyle(color: color)),
                      ]),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
