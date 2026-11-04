import '../xray/config_builder.dart';

/// What the user can change. Everything has a safe default so a new user
/// only has to add a subscription and press the button.
class Settings {
  const Settings({
    this.ruDirect = true,
    this.ruServicesOff = const [],
    this.directSites = const [],
    this.vpnSites = const [],
    this.fragmentation = true,
    this.blockQuic = true,
    this.desktopMode = TunnelMode.proxy,
    this.perAppMode = 'off',
    this.perAppPackages = const [],
    this.verboseLog = false,
    this.language = 'system',
    this.developer = false,
  });

  /// Russian sites and addresses go around the VPN.
  final bool ruDirect;

  /// Popular Russian services (ids from ru_sites.dart) that go through the
  /// VPN all the same.
  final List<String> ruServicesOff;

  /// Sites the person added that always go around the VPN, as Xray domain
  /// rules ("domain:example.com").
  final List<String> directSites;

  /// Sites that always go through the VPN, even when the Russian list has
  /// them: added by hand or taken out of the list. Xray domain rules.
  final List<String> vpnSites;

  final bool fragmentation;
  final bool blockQuic;

  /// Computers: system proxy (no administrator rights) or all traffic.
  final TunnelMode desktopMode;

  /// Which apps use the VPN: off (all), only or except. On Android the
  /// list holds package names, on Windows program names (Telegram.exe), on
  /// macOS app folders (/Applications/Telegram.app/).
  final String perAppMode;
  final List<String> perAppPackages;

  final bool verboseLog;

  /// system, ru or en.
  final String language;

  /// The settings for developers are shown.
  final bool developer;

  Settings copyWith({
    bool? ruDirect,
    List<String>? ruServicesOff,
    List<String>? directSites,
    List<String>? vpnSites,
    bool? fragmentation,
    bool? blockQuic,
    TunnelMode? desktopMode,
    String? perAppMode,
    List<String>? perAppPackages,
    bool? verboseLog,
    String? language,
    bool? developer,
  }) =>
      Settings(
        ruDirect: ruDirect ?? this.ruDirect,
        ruServicesOff: ruServicesOff ?? this.ruServicesOff,
        directSites: directSites ?? this.directSites,
        vpnSites: vpnSites ?? this.vpnSites,
        fragmentation: fragmentation ?? this.fragmentation,
        blockQuic: blockQuic ?? this.blockQuic,
        desktopMode: desktopMode ?? this.desktopMode,
        perAppMode: perAppMode ?? this.perAppMode,
        perAppPackages: perAppPackages ?? this.perAppPackages,
        verboseLog: verboseLog ?? this.verboseLog,
        language: language ?? this.language,
        developer: developer ?? this.developer,
      );

  Map<String, dynamic> toJson() => {
        'ruDirect': ruDirect,
        'ruServicesOff': ruServicesOff,
        'directSites': directSites,
        'vpnSites': vpnSites,
        'fragmentation': fragmentation,
        'blockQuic': blockQuic,
        'desktopMode': desktopMode.name,
        'perAppMode': perAppMode,
        'perAppPackages': perAppPackages,
        'verboseLog': verboseLog,
        'language': language,
        'developer': developer,
      };

  static List<String> _strings(Object? v) => [for (final p in (v as List? ?? const [])) p.toString()];

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        ruDirect: j['ruDirect'] as bool? ?? true,
        ruServicesOff: _strings(j['ruServicesOff']),
        directSites: _strings(j['directSites']),
        vpnSites: _strings(j['vpnSites']),
        fragmentation: j['fragmentation'] as bool? ?? true,
        blockQuic: j['blockQuic'] as bool? ?? true,
        desktopMode: j['desktopMode'] == 'tun' ? TunnelMode.tun : TunnelMode.proxy,
        perAppMode: j['perAppMode'] as String? ?? 'off',
        perAppPackages: _strings(j['perAppPackages']),
        verboseLog: j['verboseLog'] as bool? ?? false,
        language: j['language'] as String? ?? 'system',
        developer: j['developer'] as bool? ?? false,
      );
}
