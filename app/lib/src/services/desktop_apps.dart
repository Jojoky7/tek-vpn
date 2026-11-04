import 'dart:io';

/// A program on a computer for the list of apps that go around the VPN or
/// through it. [rule] is what goes into Xray's "process" rule: a program
/// name on Windows (Telegram.exe), the app's folder on macOS
/// (/Applications/Telegram.app/), which covers its helper processes too.
class DesktopApp {
  const DesktopApp({required this.rule, required this.name, this.detail});
  final String rule;
  final String name;
  final String? detail;
}

/// The apps in the usual folders of a Mac.
Future<List<DesktopApp>> macApps() async {
  final home = Platform.environment['HOME'];
  final dirs = [
    '/Applications',
    '/Applications/Utilities',
    '/System/Applications',
    '/System/Applications/Utilities',
    if (home != null) '$home/Applications',
  ];
  final seen = <String>{};
  final out = <DesktopApp>[];
  for (final dir in dirs) {
    try {
      await for (final e in Directory(dir).list(followLinks: false)) {
        if (!e.path.endsWith('.app')) continue;
        var path = e.path;
        if (e is Link) {
          // Safari in /Applications is a link into the system volume.
          try {
            path = await e.resolveSymbolicLinks();
          } catch (_) {
            continue;
          }
        } else if (e is! Directory) {
          continue;
        }
        final file = e.path.split('/').last;
        final name = file.substring(0, file.length - 4);
        if (name == 'Tek' || !seen.add(path)) continue;
        out.add(DesktopApp(rule: '$path/', name: name, detail: e.path));
      }
    } catch (_) {}
  }
  out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

/// What the person typed into "Add an app", as a rule; null when it is
/// not a program.
String? appRule(String input, {required bool mac}) {
  var s = input.trim();
  if (s.startsWith('"') && s.endsWith('"') && s.length > 1) s = s.substring(1, s.length - 1);
  if (s.isEmpty) return null;
  if (mac) {
    if (s.contains('/')) {
      if (s.endsWith('/')) s = s.substring(0, s.length - 1);
      if (!s.startsWith('/')) return null;
      // An app is its folder; anything else is one program by its path.
      return s.endsWith('.app') ? '$s/' : s;
    }
    final name = s.endsWith('.app') ? s.substring(0, s.length - 4) : s;
    for (final dir in ['/Applications', '/System/Applications', '/Applications/Utilities']) {
      if (Directory('$dir/$name.app').existsSync()) return '$dir/$name.app/';
    }
    return name;
  }
  s = s.replaceAll('/', r'\').split(r'\').last;
  if (s.isEmpty || s.contains(RegExp(r'[<>:"|?*]'))) return null;
  return s.toLowerCase().endsWith('.exe') ? s : '$s.exe';
}

/// How a rule reads in the list.
String appLabel(String rule) {
  var s = rule.endsWith('/') ? rule.substring(0, rule.length - 1) : rule;
  s = s.split('/').last;
  if (s.endsWith('.app')) s = s.substring(0, s.length - 4);
  return s;
}

/// Xray compares program names letter for letter, so a name typed in
/// another case also gets the usual spellings.
List<String> windowsAppRules(List<String> names) {
  final out = <String>{};
  for (final n in names) {
    final base = n.toLowerCase().endsWith('.exe') ? n.substring(0, n.length - 4) : n;
    if (base.isEmpty) continue;
    out.addAll([
      base,
      base.toLowerCase(),
      base.toUpperCase(),
      base[0].toUpperCase() + base.substring(1).toLowerCase(),
    ]);
  }
  return out.toList();
}
