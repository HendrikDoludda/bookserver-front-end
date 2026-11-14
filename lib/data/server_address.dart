/// Why a typed server address can't be used.
enum AddressProblem { invalid, insecure, notABookserver }

class AddressException implements Exception {
  const AddressException(this.problem);

  final AddressProblem problem;

  @override
  String toString() => 'AddressException(${problem.name})';
}

// `Uri` accepts a space or a non-ASCII letter in a host by percent-encoding it, so the host
// gets its own check.
final _hostCharacters = RegExp(r'^[a-z0-9._:-]+$');

/// The server's origin (scheme, host and port) from what someone typed. Without a scheme the
/// address counts as `https://`; `http://` passes only when [allowHttp] is true.
Uri parseServerAddress(String typed, {required bool allowHttp}) {
  final text = typed.trim();
  final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
  if (uri == null || !_isOrigin(uri)) {
    throw const AddressException(AddressProblem.invalid);
  }
  if (uri.scheme == 'http' && !allowHttp) {
    throw const AddressException(AddressProblem.insecure);
  }
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
  );
}

bool _isOrigin(Uri uri) =>
    (uri.scheme == 'https' || uri.scheme == 'http') &&
    _hostCharacters.hasMatch(uri.host) &&
    (!uri.hasPort || (uri.port >= 1 && uri.port <= 65535)) &&
    uri.userInfo.isEmpty &&
    (uri.path.isEmpty || uri.path == '/') &&
    !uri.hasQuery &&
    !uri.hasFragment;
