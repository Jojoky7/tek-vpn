import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../xray/config_builder.dart';
import '../state/app_state.dart';
import 'add_subscription_screen.dart';
import 'app_scope.dart';
import 'apps_screen.dart';
import 'developer_screen.dart';
import 'ru_sites_screen.dart';
import 'strings.dart';
import 'theme.dart';
import 'widgets.dart';

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
                SectionTitle(s.subscription),
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
                  ]),
                ),
                SectionTitle(s.connection),
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
                    ListTile(
                      title: Text(s.ruDirect),
                      subtitle: Text(st.ruDirect ? s.ruDirectHint : s.ruSitesOff),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => const RuSitesScreen())),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Switch(
                          value: st.ruDirect,
                          onChanged: (v) => app.updateSettings(st.copyWith(ruDirect: v)),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right_rounded),
                      ]),
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      title: Text(s.apps),
                      subtitle: Text(switch (st.perAppMode) {
                        'only' when st.perAppPackages.isNotEmpty =>
                          '${s.appsOnly} · ${st.perAppPackages.length}',
                        'except' when st.perAppPackages.isNotEmpty =>
                          '${s.appsExcept} · ${st.perAppPackages.length}',
                        _ => s.appsAll,
                      }),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => const AppsScreen())),
                    ),
                  ]),
                ),
                SectionTitle(s.appSection),
                Card(
                  child: Column(children: [
                    if (app.isAndroid) ...[
                      ListTile(
                        leading: const Icon(Icons.dashboard_customize_outlined),
                        title: Text(s.quickTile),
                        subtitle: Text(s.quickTileHint),
                        onTap: () => _addTile(app),
                      ),
                      const Divider(indent: 16, endIndent: 16),
                    ],
                    ListTile(
                      leading: const Icon(Icons.translate_rounded),
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
                SectionTitle(s.about),
                Card(
                  child: Column(children: [
                    ListTile(
                      title: Text('Tek $_version'),
                      subtitle: Text('Xray-core $_xray · ${Platform.operatingSystem}'),
                      onTap: () => _versionTapped(app),
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
                    if (st.developer) ...[
                      const Divider(indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.code_rounded),
                        title: Text(s.developer),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _openDeveloper,
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

  int _taps = 0;

  void _openDeveloper() => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const DeveloperScreen()));

  /// Five taps on the version open the settings for developers, the way
  /// Android hides its own.
  void _versionTapped(AppState app) {
    final s = S.current;
    final messenger = ScaffoldMessenger.of(context);
    if (app.settings.developer) {
      _openDeveloper();
      return;
    }
    _taps++;
    messenger.hideCurrentSnackBar();
    if (_taps >= 5) {
      _taps = 0;
      app.updateSettings(app.settings.copyWith(developer: true));
      messenger.showSnackBar(SnackBar(content: Text(s.developerOn)));
      _openDeveloper();
    } else if (_taps >= 2) {
      messenger.showSnackBar(SnackBar(
          content: Text(s.developerTaps(5 - _taps)), duration: const Duration(seconds: 1)));
    }
  }

  Future<void> _addTile(AppState app) async {
    final s = S.current;
    final result = await app.engine.requestTile();
    if (!mounted) return;
    switch (result) {
      case 'added' || 'already':
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result == 'added' ? s.tileAdded : s.tileAlready)));
      case 'declined':
        break;
      default:
        // Before Android 13 the button can only be dragged in by hand.
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(s.quickTile),
            content: Text(s.tileManual),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(s.ok))],
          ),
        );
    }
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
