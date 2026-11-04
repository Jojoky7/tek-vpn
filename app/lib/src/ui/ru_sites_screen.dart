import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/settings.dart';
import '../state/app_state.dart';
import '../xray/ru_sites.dart';
import 'app_scope.dart';
import 'strings.dart';
import 'widgets.dart';

/// The sites that go around the VPN: the Russian list, popular services one
/// by one, and sites the person adds. Changes apply when the screen closes,
/// so a connection is not restarted on every tap.
class RuSitesScreen extends StatefulWidget {
  const RuSitesScreen({super.key});

  @override
  State<RuSitesScreen> createState() => _RuSitesScreenState();
}

class _RuSitesScreenState extends State<RuSitesScreen> {
  late final AppState _app;
  late final ValueNotifier<Settings> _draft;
  List<String>? _list;

  @override
  void initState() {
    super.initState();
    _app = AppScope.read(context);
    _draft = ValueNotifier(_app.settings)..addListener(() => setState(() {}));
    rootBundle.load('assets/geo/geosite.dat').then((data) {
      final rules = geositeRules(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          'category-ru');
      if (mounted) setState(() => _list = rules);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    final d = _draft.value, now = _app.settings;
    if (d.ruDirect != now.ruDirect ||
        !listEquals(d.ruServicesOff, now.ruServicesOff) ||
        !listEquals(d.directSites, now.directSites) ||
        !listEquals(d.vpnSites, now.vpnSites)) {
      _app.updateSettings(now.copyWith(
        ruDirect: d.ruDirect,
        ruServicesOff: d.ruServicesOff,
        directSites: d.directSites,
        vpnSites: d.vpnSites,
      ));
    }
    _draft.dispose();
    super.dispose();
  }

  Settings get _st => _draft.value;

  void _toggleService(RuService r, bool on) {
    final off = {..._st.ruServicesOff};
    on ? off.remove(r.id) : off.add(r.id);
    _draft.value = _st.copyWith(ruServicesOff: off.toList()..sort());
  }

  void _removeSite(String rule) => _draft.value = _st.copyWith(
        directSites: [..._st.directSites]..remove(rule),
        vpnSites: [..._st.vpnSites]..remove(rule),
      );

  Future<void> _addSite() async {
    final s = S.current;
    final text = TextEditingController();
    var direct = true;
    String? error;
    final added = await showDialog<(String, bool)>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setDialog) {
        void submit() {
          final rule = siteRule(text.text);
          if (rule == null) {
            setDialog(() => error = s.badSite);
            return;
          }
          Navigator.pop(c, (rule, direct));
        }

        return AlertDialog(
          title: Text(s.addSite),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: text,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(hintText: 'example.com', errorText: error),
              onSubmitted: (_) => submit(),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, label: Text(s.siteDirect)),
                ButtonSegment(value: false, label: Text(s.siteVpn)),
              ],
              selected: {direct},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setDialog(() => direct = v.first),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text(s.cancel)),
            TextButton(onPressed: submit, child: Text(s.add)),
          ],
        );
      }),
    );
    text.dispose();
    if (added == null) return;
    final (rule, toDirect) = added;
    final directSites = [..._st.directSites]..remove(rule);
    final vpnSites = [..._st.vpnSites]..remove(rule);
    (toDirect ? directSites : vpnSites).add(rule);
    _draft.value = _st.copyWith(directSites: directSites, vpnSites: vpnSites);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    final st = _st;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final off = st.ruServicesOff.toSet();
    final list = _list;
    final mine = [
      for (final r in st.directSites) (r, true),
      for (final r in st.vpnSites) (r, false),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(s.ruSites)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Card(
                  child: SwitchListTile(
                    title: Text(s.ruDirect),
                    subtitle: Text(s.ruSitesHint),
                    value: st.ruDirect,
                    onChanged: (v) => _draft.value = st.copyWith(ruDirect: v),
                  ),
                ),
                SectionTitle(s.mySites, hint: s.mySitesHint),
                Card(
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.add_rounded),
                      title: Text(s.addSite),
                      onTap: _addSite,
                    ),
                    for (final (rule, direct) in mine) ...[
                      const Divider(indent: 16, endIndent: 16),
                      ListTile(
                        leading: Icon(direct ? Icons.north_east_rounded : Icons.shield_outlined),
                        title: Text(siteLabel(rule), maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(direct ? s.siteDirect : s.siteVpn),
                        trailing: IconButton(
                          tooltip: s.remove,
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => _removeSite(rule),
                        ),
                      ),
                    ],
                  ]),
                ),
                SectionTitle(s.popularServices, hint: st.ruDirect ? s.popularHint : s.ruSitesOff),
                Card(
                  child: Column(children: [
                    for (var i = 0; i < ruServices.length; i++) ...[
                      if (i > 0) const Divider(indent: 16, endIndent: 16),
                      SwitchListTile(
                        dense: true,
                        title: Text(s.ru ? ruServices[i].ru : ruServices[i].en,
                            style: const TextStyle(fontSize: 15)),
                        subtitle: Text(ruServices[i].domains.join(', '),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        value: st.ruDirect && !off.contains(ruServices[i].id),
                        onChanged: st.ruDirect ? (v) => _toggleService(ruServices[i], v) : null,
                      ),
                    ],
                  ]),
                ),
                SectionTitle(s.fullList),
                Card(
                  child: ListTile(
                    enabled: st.ruDirect && list != null,
                    title: Text(s.fullList),
                    subtitle: Text(list == null
                        ? ''
                        : s.fullListCount(list.where((r) => !_isZone(r)).length)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: list == null
                        ? null
                        : () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => _FullListScreen(rules: list, draft: _draft))),
                  ),
                ),
                if (!st.ruDirect && mine.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
                    child: Text(s.ruSitesOff, style: TextStyle(color: muted)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A whole zone, such as "domain:ru".
bool _isZone(String rule) => rule.startsWith('domain:') && !rule.substring(7).contains('.');

/// Every entry of the Russian list; an unchecked one goes through the VPN.
class _FullListScreen extends StatefulWidget {
  const _FullListScreen({required this.rules, required this.draft});
  final List<String> rules;
  final ValueNotifier<Settings> draft;

  @override
  State<_FullListScreen> createState() => _FullListScreenState();
}

class _FullListScreenState extends State<_FullListScreen> {
  String _query = '';
  late final List<String> _rules = [
    ...widget.rules.where(_isZone),
    ...widget.rules.where((r) => !_isZone(r)).toList()
      ..sort((a, b) => siteLabel(a).compareTo(siteLabel(b))),
  ];

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ValueListenableBuilder<Settings>(
      valueListenable: widget.draft,
      builder: (context, st, _) {
        final vpn = st.vpnSites.toSet();
        final q = _query.trim().toLowerCase();
        final shown = q.isEmpty
            ? _rules
            : _rules.where((r) => siteLabel(r).contains(q) || r.contains(q)).toList();
        return Scaffold(
          appBar: AppBar(title: Text(s.fullList)),
          body: Column(children: [
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
                child: Text(s.fullListHint, style: TextStyle(color: muted)),
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? Center(child: Text(s.nothingFound, style: TextStyle(color: muted)))
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final rule = shown[i];
                        return CheckboxListTile(
                          dense: true,
                          value: !vpn.contains(rule),
                          title: Text(siteLabel(rule), style: const TextStyle(fontSize: 15)),
                          onChanged: (v) {
                            final list = [...st.vpnSites]..remove(rule);
                            if (v == false) list.add(rule);
                            widget.draft.value = st.copyWith(vpnSites: list);
                          },
                        );
                      },
                    ),
            ),
          ]),
        );
      },
    );
  }
}
