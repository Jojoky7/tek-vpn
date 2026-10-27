import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../xray/config_builder.dart';

class NetResponse {
  NetResponse(this.status, this.headers, this.body);
  final int status;

  /// Header names in lower case; repeated headers joined with ", ".
  final Map<String, String> headers;
  final String body;
}

/// Thrown when the server could not be reached at all.
class NetworkException implements Exception {
  NetworkException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Plain HTTPS requests for the subscription and tekvpn.com. With [via]
/// the request goes through the running VPN (Tek's own local proxy), for
/// networks where tekvpn.com itself is blocked.
Future<NetResponse> httpRequest(
  String method,
  Uri url, {
  Map<String, String> headers = const {},
  Object? jsonBody,
  ApiProxy? via,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final client = HttpClient()
    ..connectionTimeout = timeout
    ..userAgent = null
    ..findProxy = (_) => via == null
        ? 'DIRECT'
        : 'PROXY ${via.user}:${via.pass}@127.0.0.1:${via.port}';
  try {
    final req = await client.openUrl(method, url).timeout(timeout);
    req.followRedirects = true;
    req.maxRedirects = 5;
    headers.forEach(req.headers.set);
    if (jsonBody != null) {
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(jsonBody)));
    }
    final resp = await req.close().timeout(timeout);
    final bytes = await resp
        .fold<List<int>>(<int>[], (a, b) => a..addAll(b))
        .timeout(timeout);
    final out = <String, String>{};
    resp.headers.forEach((name, values) => out[name.toLowerCase()] = values.join(', '));
    return NetResponse(resp.statusCode, out, utf8.decode(bytes, allowMalformed: true));
  } on TimeoutException {
    throw NetworkException('timeout');
  } on SocketException catch (e) {
    throw NetworkException(e.osError?.message ?? e.message);
  } on HandshakeException catch (e) {
    throw NetworkException('TLS: ${e.message}');
  } on HttpException catch (e) {
    throw NetworkException(e.message);
  } finally {
    client.close(force: true);
  }
}
