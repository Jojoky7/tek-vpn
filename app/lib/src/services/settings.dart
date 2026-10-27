import '../xray/config_builder.dart';

/// What the user can change. Everything has a safe default so a new user
/// only has to add a subscription and press the button.
class Settings {
  const Settings({
    this.ruDirect = true,
    this.fragmentation = true,
    this.blockQuic = true,
    this.desktopMode = TunnelMode.proxy,
    this.perAppMode = 'off',
    this.perAppPackages = const [],
    this.verboseLog = false,
    this.language = 'system',
  });

  final bool ruDirect;
  final bool fragmentation;
  final bool blockQuic;

  /// Computers: system proxy (no administrator rights) or all traffic.
  final TunnelMode desktopMode;

  /// Android: off, only or except.
  final String perAppMode;
  final List<String> perAppPackages;

  final bool verboseLog;

  /// system, ru or en.
  final String language;

  Settings copyWith({
    bool? ruDirect,
    bool? fragmentation,
    bool? blockQuic,
    TunnelMode? desktopMode,
    String? perAppMode,
    List<String>? perAppPackages,
    bool? verboseLog,
    String? language,
  }) =>
      Settings(
        ruDirect: ruDirect ?? this.ruDirect,
        fragmentation: fragmentation ?? this.fragmentation,
        blockQuic: blockQuic ?? this.blockQuic,
        desktopMode: desktopMode ?? this.desktopMode,
        perAppMode: perAppMode ?? this.perAppMode,
        perAppPackages: perAppPackages ?? this.perAppPackages,
        verboseLog: verboseLog ?? this.verboseLog,
        language: language ?? this.language,
      );

  Map<String, dynamic> toJson() => {
        'ruDirect': ruDirect,
        'fragmentation': fragmentation,
        'blockQuic': blockQuic,
        'desktopMode': desktopMode.name,
        'perAppMode': perAppMode,
        'perAppPackages': perAppPackages,
        'verboseLog': verboseLog,
        'language': language,
      };

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        ruDirect: j['ruDirect'] as bool? ?? true,
        fragmentation: j['fragmentation'] as bool? ?? true,
        blockQuic: j['blockQuic'] as bool? ?? true,
        desktopMode: j['desktopMode'] == 'tun' ? TunnelMode.tun : TunnelMode.proxy,
        perAppMode: j['perAppMode'] as String? ?? 'off',
        perAppPackages: [
          for (final p in (j['perAppPackages'] as List? ?? const [])) p.toString()
        ],
        verboseLog: j['verboseLog'] as bool? ?? false,
        language: j['language'] as String? ?? 'system',
      );
}
