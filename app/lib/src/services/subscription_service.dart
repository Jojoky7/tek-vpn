import 'dart:io';

import '../model/subscription.dart';
import '../parse/subscription_parser.dart';
import '../xray/config_builder.dart';
import 'net.dart';

/// Why a subscription could not be loaded, in words for the user.
class SubscriptionException implements Exception {
  SubscriptionException(this.kind, [this.detail]);

  /// notFound, network, format or http.
  final String kind;
  final String? detail;

  @override
  String toString() => detail == null ? kind : '$kind: $detail';
}

/// Downloads and parses subscriptions.
class SubscriptionService {
  SubscriptionService(this.appVersion);

  final String appVersion;

  /// Tek's own name first, so the panel shows which app a user has. If a
  /// panel answers that name with something Tek cannot read, the Happ and
  /// v2rayNG names get the plain formats every panel supports.
  List<String> get userAgents => [
        'Tek/$appVersion (${Platform.operatingSystem})',
        'Happ/3.7.0',
        'v2rayNG/1.10.20',
      ];

  /// Accepts what people paste: a link with spaces around it, without the
  /// scheme, or a tek:// / happ:// import link.
  static String? normalizeUrl(String input) {
    var s = input.trim();
    for (final prefix in const ['tek://add/', 'tek://import/', 'happ://add/']) {
      if (s.toLowerCase().startsWith(prefix)) s = s.substring(prefix.length);
    }
    if (s.toLowerCase().startsWith('tek://subscribe?') ||
        s.toLowerCase().startsWith('tek://import?')) {
      s = Uri.tryParse(s)?.queryParameters['url'] ?? '';
    }
    // A link inside a link may arrive percent-encoded, or with the double
    // slash after the scheme folded into one.
    if (RegExp(r'^https?%3a', caseSensitive: false).hasMatch(s)) {
      try {
        s = Uri.decodeComponent(s);
      } catch (_) {}
    }
    s = s.replaceFirstMapped(
        RegExp(r'^(https?):/(?!/)', caseSensitive: false), (m) => '${m[1]}://');
    if (!s.contains('://') && s.contains('.') && !s.contains(' ')) s = 'https://$s';
    final uri = Uri.tryParse(s);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http')) || uri.host.isEmpty) {
      return null;
    }
    return s;
  }

  Future<Subscription> fetch(String url, {ApiProxy? via}) async {
    final uri = Uri.parse(url);
    SubscriptionException? last;
    for (final ua in userAgents) {
      NetResponse resp;
      try {
        resp = await _get(uri, ua, via);
      } on SubscriptionException catch (e) {
        if (e.kind == 'network') rethrow;
        last = e;
        continue;
      }
      if (resp.status == 404 || resp.status == 410) {
        throw SubscriptionException('notFound');
      }
      if (resp.status != 200) {
        last = SubscriptionException('http', 'HTTP ${resp.status}');
        continue;
      }
      try {
        final parsed = parseSubscription(resp.body, headers: resp.headers);
        return Subscription(
          url: url,
          info: parsed.info,
          servers: parsed.servers,
          updatedAt: DateTime.now(),
        );
      } on SubscriptionFormatException catch (e) {
        last = SubscriptionException('format', e.message);
      }
    }
    throw last ?? SubscriptionException('format');
  }

  Future<NetResponse> _get(Uri uri, String ua, ApiProxy? via) async {
    final headers = {'User-Agent': ua, 'Accept': '*/*'};
    try {
      return await httpRequest('GET', uri, headers: headers);
    } on NetworkException catch (e) {
      if (via == null) throw SubscriptionException('network', e.message);
    }
    try {
      return await httpRequest('GET', uri, headers: headers, via: via);
    } on NetworkException catch (e) {
      throw SubscriptionException('network', e.message);
    }
  }
}
