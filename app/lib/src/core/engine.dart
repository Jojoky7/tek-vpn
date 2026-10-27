import 'dart:async';

import '../xray/config_builder.dart';

/// Where the connection is.
enum CoreState { stopped, starting, running, stopping }

class EngineStatus {
  const EngineStatus(this.state,
      {this.since, this.error, this.up = 0, this.down = 0, this.mode, this.serverId});

  static const stopped = EngineStatus(CoreState.stopped);

  final CoreState state;

  /// When the connection came up.
  final DateTime? since;

  /// Why the last start failed or the connection dropped.
  final String? error;

  /// Bytes through the VPN since it came up.
  final int up;
  final int down;

  final TunnelMode? mode;

  /// The server the running VPN was started with (Android keeps running
  /// after the screen is closed, so the app asks it on the next start).
  final String? serverId;

  bool get running => state == CoreState.running;
}

class PingResult {
  const PingResult(this.ms, {this.error});

  /// -1 when the server did not answer.
  final int ms;
  final String? error;

  bool get ok => ms >= 0;

  factory PingResult.fromJson(Map<String, dynamic> j) =>
      PingResult((j['ms'] as num?)?.toInt() ?? -1, error: j['error'] as String?);
}

class LogLine {
  const LogLine(this.id, this.time, this.level, this.text);
  final int id;
  final DateTime time;
  final String level;
  final String text;

  factory LogLine.fromJson(Map<String, dynamic> j) => LogLine(
        (j['id'] as num).toInt(),
        DateTime.tryParse(j['time']?.toString() ?? '') ?? DateTime.now(),
        j['level']?.toString() ?? 'info',
        j['text']?.toString() ?? '',
      );
}

/// Thrown when the connection needs administrator rights (the "all
/// traffic" mode on a computer) and the core does not have them.
class NeedsAdminException implements Exception {
  @override
  String toString() => 'needs administrator rights';
}

/// Thrown when the user did not allow the VPN (Android's system dialog) or
/// the administrator prompt.
class PermissionDeniedException implements Exception {
  @override
  String toString() => 'permission denied';
}

/// Android-only settings for the VPN interface.
class AndroidVpnOptions {
  const AndroidVpnOptions({this.perAppMode = 'off', this.packages = const []});

  /// off, only (only the listed apps use the VPN) or except (the listed
  /// apps go around it).
  final String perAppMode;
  final List<String> packages;

  Map<String, dynamic> toJson() => {'perAppMode': perAppMode, 'packages': packages};
}

/// The part of Tek that runs Xray: in-process on Android, a background
/// "tek-core" process on Windows and macOS.
abstract class TekEngine {
  /// Whether the user can choose between the proxy and the TUN mode.
  bool get supportsModes;

  Stream<EngineStatus> get status;
  EngineStatus get current;

  /// The folder with geoip.dat and geosite.dat.
  String get assetDir;

  Future<void> init(String assetDir);

  Future<void> start(
    Map<String, dynamic> config, {
    required TunnelMode mode,
    required ConnectOptions options,
    AndroidVpnOptions android = const AndroidVpnOptions(),
    String serverName = '',
    String serverId = '',
  });

  Future<void> stop();

  /// Checks servers by a real request through each outbound tag, one after
  /// another. [probeConfig] is used only while disconnected.
  Future<List<PingResult>> realPing(
    Map<String, dynamic> probeConfig,
    List<String> tags, {
    String url = 'https://www.gstatic.com/generate_204',
    int timeoutMs = 5000,
    int attempts = 2,
  });

  /// Measures the time to open a TCP connection to each server.
  Future<List<PingResult>> tcpPing(List<({String host, int port})> targets,
      {int timeoutMs = 3000, int attempts = 2});

  Future<void> cancelPing();

  Future<List<LogLine>> logs(int sinceId);

  Future<void> setLogLevel(String level);

  /// Returns null when Xray accepts the config, or the error.
  Future<String?> validate(Map<String, dynamic> config);

  Future<String> version();

  /// Restarts the core with administrator rights (computers only).
  Future<void> elevate() async {}

  bool get elevated => true;

  Future<void> dispose();
}
