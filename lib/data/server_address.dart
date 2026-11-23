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

// Traffic to these never leaves the device, so plain HTTP can't be read or changed on the way.
// Exact names only: `localhost.example.com` is someone else's server.
const _thisDevice = {'localhost', '127.0.0.1', '::1'};

/// The server's origin (scheme, host and port) from what someone typed. Without a scheme the
/// address counts as `https://`; `http://` passes when [allowHttp] is true, and otherwise only to
/// this device itself: `localhost`, `127.0.0.1` or `::1`.
Uri parseServerAddress(String typed, {required bool allowHttp}) {
  final text = typed.trim();
  final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
  if (uri == null || !_isOrigin(uri)) {
    throw const AddressException(AddressProblem.invalid);
  }
  if (uri.scheme == 'http' && !allowHttp && !_thisDevice.contains(uri.host)) {
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
