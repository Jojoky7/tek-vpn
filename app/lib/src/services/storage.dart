import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../model/subscription.dart';
import 'settings.dart';

/// Server check results kept between launches, so the list has its dots
/// right away.
class CheckResult {
  const CheckResult({this.alive, this.tcpMs, this.realMs, this.at});

  /// null until the real check has run.
  final bool? alive;
  final int? tcpMs;
  final int? realMs;
  final DateTime? at;

  Map<String, dynamic> toJson() => {
        if (alive != null) 'alive': alive,
        if (tcpMs != null) 'tcpMs': tcpMs,
        if (realMs != null) 'realMs': realMs,
        if (at != null) 'at': at!.millisecondsSinceEpoch,
      };

  factory CheckResult.fromJson(Map<String, dynamic> j) => CheckResult(
        alive: j['alive'] as bool?,
        tcpMs: j['tcpMs'] as int?,
        realMs: j['realMs'] as int?,
        at: j['at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
      );
}

/// Everything Tek keeps on the device. Nothing leaves it.
class Storage {
  Storage(this._prefs);

  final SharedPreferences _prefs;

  static Future<Storage> open() async =>
      Storage(await SharedPreferences.getInstance());

  static const _kSubscription = 'subscription';
  static const _kSettings = 'settings';
  static const _kSelected = 'selectedServer';
  static const _kChecks = 'checks';
  static const _kAccount = 'account';
  static const _kTrayHint = 'trayHintShown';
  static const _kTileOffered = 'tileOffered';

  bool get trayHintShown => _prefs.getBool(_kTrayHint) ?? false;

  Future<void> setTrayHintShown() => _prefs.setBool(_kTrayHint, true);

  /// Android: the system was asked once to add the quick settings button.
  bool get tileOffered => _prefs.getBool(_kTileOffered) ?? false;

  Future<void> setTileOffered() => _prefs.setBool(_kTileOffered, true);

  Subscription? get subscription {
    final raw = _prefs.getString(_kSubscription);
    if (raw == null) return null;
    try {
      return Subscription.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> setSubscription(Subscription? s) => s == null
      ? _prefs.remove(_kSubscription)
      : _prefs.setString(_kSubscription, jsonEncode(s.toJson()));

  Settings get settings {
    final raw = _prefs.getString(_kSettings);
    if (raw == null) return const Settings();
    try {
      return Settings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const Settings();
    }
  }

  Future<void> setSettings(Settings s) =>
      _prefs.setString(_kSettings, jsonEncode(s.toJson()));

  /// The chosen server id, or null for "fastest".
  String? get selectedServer => _prefs.getString(_kSelected);

  Future<void> setSelectedServer(String? id) => id == null
      ? _prefs.remove(_kSelected)
      : _prefs.setString(_kSelected, id);

  Map<String, CheckResult> get checks {
    final raw = _prefs.getString(_kChecks);
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in m.entries)
          e.key: CheckResult.fromJson(Map<String, dynamic>.from(e.value as Map))
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> setChecks(Map<String, CheckResult> checks) => _prefs.setString(
      _kChecks, jsonEncode({for (final e in checks.entries) e.key: e.value.toJson()}));

  /// Versions before 1.2 signed in to tekvpn.com with an email and kept the
  /// session here. Tek no longer signs in, so the old token is dropped.
  Future<void> forgetAccount() => _prefs.remove(_kAccount);
}
