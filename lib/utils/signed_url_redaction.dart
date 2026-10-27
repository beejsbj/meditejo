/// Keeps signed YouTube stream addresses out of logs. One works for anyone who
/// holds it until it expires, and logcat is pasted into bug reports. Only the
/// host survives, so a log still says which server failed.
final _address = RegExp(r'''https?://[^\s"'<>)\]]+''');

String redactSignedUrls(String text) => text.replaceAllMapped(_address, (m) {
  final uri = Uri.tryParse(m[0]!);
  if (uri == null) {
    // Unparseable, so judge by its text rather than let it through.
    return _looksSigned(m[0]!) ? 'https://unknown/<redacted>' : m[0]!;
  }
  return _isSigned(uri) ? 'https://${uri.host}/<redacted>' : m[0]!;
});

/// A stream address: a googlevideo.com host, or a `/videoplayback` path.
bool _isSigned(Uri uri) {
  final host = uri.host.toLowerCase();
  return host == 'googlevideo.com' ||
      host.endsWith('.googlevideo.com') ||
      uri.path.startsWith('/videoplayback');
}

bool _looksSigned(String text) {
  final lower = text.toLowerCase();
  return lower.contains('googlevideo.com') || lower.contains('/videoplayback');
}
