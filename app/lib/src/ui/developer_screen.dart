import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'logs_screen.dart';
import 'strings.dart';

/// Settings that only matter when something does not work. Hidden until
/// the version in the settings is tapped five times.
class DeveloperScreen extends StatelessWidget {
  const DeveloperScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = S.current;
    final st = app.settings;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: Text(s.developer)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
                  child: Text(s.developerHint, style: TextStyle(color: muted, height: 1.35)),
                ),
                Card(
                  child: Column(children: [
                    SwitchListTile(
                      title: Text(s.fragmentation),
                      subtitle: Text(s.fragmentationHint),
                      value: st.fragmentation,
                      onChanged: (v) => app.updateSettings(st.copyWith(fragmentation: v)),
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    SwitchListTile(
                      title: Text(s.blockQuic),
                      subtitle: Text(s.blockQuicHint),
                      value: st.blockQuic,
                      onChanged: (v) => app.updateSettings(st.copyWith(blockQuic: v)),
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    SwitchListTile(
                      title: Text(s.verboseLog),
                      subtitle: Text(s.verboseLogHint),
                      value: st.verboseLog,
                      onChanged: (v) => app.updateSettings(st.copyWith(verboseLog: v)),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    title: Text(s.logs),
                    subtitle: Text(s.logsHint),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => const LogsScreen())),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: TextButton(
                    onPressed: () {
                      app.updateSettings(st.copyWith(developer: false));
                      Navigator.of(context).pop();
                    },
                    child: Text(s.developerHide),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
