import 'dart:convert';

import '../xray/config_builder.dart';
import 'net.dart';

class TekApiException implements Exception {
  TekApiException(this.message, {this.code});

  /// The server's own words when it gave any.
  final String message;

  /// email_taken, unauthorized, network...
  final String? code;

  @override
  String toString() => message;
}

/// A key (subscription) of the tekvpn.com account.
class TekKey {
  TekKey(this.subToken, this.active, this.expiresAt);
  final String subToken;
  final bool active;
  final DateTime? expiresAt;

  String get subscriptionUrl => 'https://tekvpn.com/sub/$subToken';
}

/// The tekvpn.com account: sign in with email and password and take the
/// subscription link from it, the same way the site's dashboard does.
class TekApi {
  TekApi({this.base = 'https://tekvpn.com/api/v1'});

  final String base;

  static bool isGmail(String email) =>
      RegExp(r'^[^@\s]+@gmail\.com$', caseSensitive: false).hasMatch(email.trim());

  Future<String> login(String email, String password, {ApiProxy? via}) =>
      _auth('/auth/login', email, password, via);

  Future<String> register(String email, String password, {ApiProxy? via}) =>
      _auth('/auth/email/register', email, password, via);

  Future<String> _auth(String path, String email, String password, ApiProxy? via) async {
    final r = await _send('POST', path,
        body: {'email': email.trim(), 'password': password}, via: via);
    final token = (r is Map) ? r['token']?.toString() : null;
    if (token == null || token.isEmpty) {
      throw TekApiException('the site did not return a session');
    }
    return token;
  }

  Future<List<TekKey>> keys(String token, {ApiProxy? via}) async {
    final r = await _send('GET', '/keys', token: token, via: via);
    final list = r is List ? r : (r is Map ? (r['keys'] ?? r['items']) : null);
    if (list is! List) return const [];
    return [
      for (final k in list.whereType<Map>())
        if ((k['sub_token']?.toString() ?? '').isNotEmpty)
          TekKey(
            k['sub_token'].toString(),
            k['is_active'] != false,
            DateTime.tryParse(k['expires_at']?.toString() ?? ''),
          )
    ];
  }

  /// Asks for the free trial the site gives new accounts.
  Future<void> trial(String token, {ApiProxy? via}) =>
      _send('POST', '/keys/trial', token: token, body: const {}, via: via);

  Future<dynamic> _send(String method, String path,
      {String? token, Object? body, ApiProxy? via}) async {
    final headers = {
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    NetResponse resp;
    try {
      resp = await httpRequest(method, Uri.parse('$base$path'),
          headers: headers, jsonBody: body);
    } on NetworkException catch (e) {
      if (via == null) throw TekApiException(e.message, code: 'network');
      try {
        resp = await httpRequest(method, Uri.parse('$base$path'),
            headers: headers, jsonBody: body, via: via);
      } on NetworkException catch (e) {
        throw TekApiException(e.message, code: 'network');
      }
    }
    dynamic decoded;
    try {
      decoded = resp.body.isEmpty ? null : jsonDecode(resp.body);
    } catch (_) {
      decoded = null;
    }
    if (resp.status >= 200 && resp.status < 300) return decoded;
    final map = decoded is Map ? decoded : const {};
    final message = (map['error'] ?? map['message'] ?? map['detail'])?.toString();
    throw TekApiException(message ?? 'HTTP ${resp.status}',
        code: map['code']?.toString() ??
            (resp.status == 401 ? 'unauthorized' : null));
  }
}
