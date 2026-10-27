import 'dart:convert';

/// Decodes standard or URL-safe base64, with or without padding and line
/// breaks. Returns null when the text is not base64 of valid UTF-8.
String? tryDecodeBase64(String input) {
  var s = input.replaceAll(RegExp(r'\s'), '');
  if (s.isEmpty) return null;
  if (!RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(s)) return null;
  s = s.replaceAll('-', '+').replaceAll('_', '/').replaceAll('=', '');
  final pad = s.length % 4;
  if (pad == 1) return null;
  if (pad > 0) s += '=' * (4 - pad);
  try {
    return utf8.decode(base64.decode(s));
  } catch (_) {
    return null;
  }
}
