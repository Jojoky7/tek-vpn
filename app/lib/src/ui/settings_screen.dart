import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../xray/config_builder.dart';
import 'add_subscription_screen.dart';
import 'app_scope.dart';
import 'apps_screen.dart';
import 'logs_screen.dart';
import 'strings.dart';
import 'theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';
  String _xray = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = p.version);
    });
    AppScope.read(context).engine.version().then((v) {
      if (mounted) setState(() => _xray = v);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = S.current;
    final st = app.settings;
    final sub = app.subscription;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(s.settings)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                _Section(s.subscription),
                Card(
                  child: Column(children: [
                    if (sub != null) ...[
                      ListTile(
                        leading: const Icon(Icons.link_rounded),
                        title: Text(sub.info.title ?? Uri.tryParse(sub.url)?.host ?? sub.url,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(s.updated(s.ago(sub.updatedAt))),
                        trailing: app.refreshing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : IconButton(
                                tooltip: s.refresh,
                                icon: const Icon(Icons.refresh_rounded),
                                onPressed: () => app.refreshSubscription(),
                              ),
                      ),
                      const Divider(indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.copy_rounded),
                        title: Text(s.copy),
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: sub.url));
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(s.copied)));
                        },
                      ),
                      const Divider(indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.delete_outline_rounded, color: TekColors.red),
                        title: Text(s.remove, style: const TextStyle(color: TekColors.red)),
                        onTap: () => _confirmRemove(context),
                      ),
                    ] else
                      ListTile(
                        leading: const Icon(Icons.add_rounded),
                        title: Text(s.addSubscription),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => const AddSubscriptionScreen())),
                      ),
                    if (app.accountEmail != null) ...[
                      const Divider(indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.person_outline_rounded),
                        title: Text(app.accountEmail!),
                        subtitle: Text(s.account),
                        trailing: TextButton(onPressed: app.signOut, child: Text(s.signOut)),
                      ),
                    ],
                  ]),
                ),
                _Section(s.connection),
                Card(
                  child: Column(children: [
                    if (!app.isAndroid) ...[
                      RadioGroup<TunnelMode>(
                        groupValue: st.desktopMode,
                        onChanged: (m) {
                          if (m != null) app.updateSettings(st.copyWith(desktopMode: m));
                        },
                        child: Column(children: [
                          RadioListTile<TunnelMode>(
                            value: TunnelMode.proxy,
                            title: Text(s.modeProxy),
                            subtitle: Text(s.modeProxyHint),
                          ),
                          RadioListTile<TunnelMode>(
                            value: TunnelMode.tun,
                            title: Text(s.modeTun),
                            subtitle: Text(s.modeTunHint),
                          ),
                        ]),
                      ),
                      const Divider(indent: 16, endIndent: 16),
                    ],
                    SwitchListTile(
                      title: Text(s.ruDirect),
                      subtitle: Text(s.ruDirectHint),
                      value: st.ruDirect,
                      onChanged: (v) => app.updateSettings(st.copyWith(ruDirect: v)),
                    ),
                    if (app.isAndroid) ...[
                      const Divider(indent: 16, endIndent: 16),
                      ListTile(
                        title: Text(s.apps),
                        subtitle: Text(switch (st.perAppMode) {
                          'only' => '${s.appsOnly} · ${st.perAppPackages.length}',
                          'except' => '${s.appsExcept} · ${st.perAppPackages.length}',
                          _ => s.appsAll,
                        }),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => const AppsScreen())),
                      ),
                    ],
                  ]),
                ),
                _Section(s.advanced),
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
                      value: st.verboseLog,
                      onChanged: (v) => app.updateSettings(st.copyWith(verboseLog: v)),
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      title: Text(s.logs),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => const LogsScreen())),
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      title: Text(s.language),
                      trailing: DropdownButton<String>(
                        value: st.language,
                        underline: const SizedBox(),
                        items: [
                          DropdownMenuItem(value: 'system', child: Text(s.languageSystem)),
                          const DropdownMenuItem(value: 'ru', child: Text('Русский')),
                          const DropdownMenuItem(value: 'en', child: Text('English')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          S.use(v);
                          app.updateSettings(st.copyWith(language: v));
                        },
                      ),
                    ),
                  ]),
                ),
                _Section(s.about),
                Card(
                  child: Column(children: [
                    ListTile(
                      title: Text('Tek $_version'),
                      subtitle: Text('Xray-core $_xray · ${Platform.operatingSystem}'),
                    ),
                    if (sub?.info.supportUrl != null) ...[
                      const Divider(indent: 16, endIndent: 16),
                      ListTile(
                        title: Text(s.support),
                        trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                        onTap: () => launchUrl(Uri.parse(sub!.info.supportUrl!),
                            mode: LaunchMode.externalApplication),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: 8),
                Text('tekvpn.com',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final s = S.current;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(s.removeConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(s.remove, style: const TextStyle(color: TekColors.red)),
          ),
        ],
      ),
    );
    if (yes == true && context.mounted) await AppScope.read(context).removeSubscription();
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
        child: Text(title.toUpperCase(),
            style: TextStyle(
                fontSize: 12,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}
