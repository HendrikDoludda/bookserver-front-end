import 'package:bookserver/data/auth_api.dart';

/// What the app keeps about its server: the origin, the device id the server gave, and the
/// session while one is open. One record, so a session can't outlive or change its server.
class StoredConnection {
  const StoredConnection({required this.server, this.deviceId, this.tokens});

  factory StoredConnection.fromJson(Object? json) {
    if (json case {
      'server': String server,
      'device_id': String? deviceId,
      'tokens': final Object? tokens,
    }) {
      final origin = Uri.tryParse(server);
      if (origin != null && origin.host.isNotEmpty) {
        return StoredConnection(
          server: origin,
          deviceId: deviceId,
          tokens: tokens == null ? null : SessionTokens.fromJson(tokens),
        );
      }
    }
    throw const FormatException('Not a stored connection.');
  }

  final Uri server;
  final String? deviceId;
  final SessionTokens? tokens;

  StoredConnection withTokens(SessionTokens tokens) => StoredConnection(
    server: server,
    deviceId: tokens.deviceId,
    tokens: tokens,
  );

  StoredConnection withoutTokens() =>
      StoredConnection(server: server, deviceId: deviceId);

  Map<String, Object?> toJson() => {
    'server': server.toString(),
    'device_id': deviceId,
    'tokens': tokens?.toJson(),
  };
}
