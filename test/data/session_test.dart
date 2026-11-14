import 'dart:convert';

import 'package:bookserver/data/auth_api.dart';
import 'package:bookserver/data/session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final origin = Uri.parse('https://books.example.ts.net');
  final tokens = SessionTokens(
    sessionToken: 'session-1',
    sessionExpiresAt: DateTime.utc(2026, 11, 14, 12, 15),
    refreshToken: 'refresh-1',
    refreshExpiresAt: DateTime.utc(2026, 12, 14, 12),
    deviceId: 'device-1',
  );

  StoredConnection throughJson(StoredConnection connection) =>
      StoredConnection.fromJson(jsonDecode(jsonEncode(connection.toJson())));

  test('goes through JSON and back with its session', () {
    final copy = throughJson(
      StoredConnection(server: origin, deviceId: 'device-1', tokens: tokens),
    );

    expect(copy.server, origin);
    expect(copy.deviceId, 'device-1');
    expect(copy.tokens?.sessionToken, 'session-1');
    expect(copy.tokens?.sessionExpiresAt, DateTime.utc(2026, 11, 14, 12, 15));
    expect(copy.tokens?.refreshToken, 'refresh-1');
    expect(copy.tokens?.refreshExpiresAt, DateTime.utc(2026, 12, 14, 12));
    expect(copy.tokens?.deviceId, 'device-1');
  });

  test('goes through JSON and back without a session', () {
    final copy = throughJson(StoredConnection(server: origin));

    expect(copy.server, origin);
    expect(copy.deviceId, isNull);
    expect(copy.tokens, isNull);
  });

  test('a session brings its device id, and signing out keeps it', () {
    final signedIn = StoredConnection(server: origin).withTokens(tokens);
    expect(signedIn.deviceId, 'device-1');

    final signedOut = signedIn.withoutTokens();
    expect(signedOut.server, origin);
    expect(signedOut.deviceId, 'device-1');
    expect(signedOut.tokens, isNull);
  });

  test('refuses a record of another shape', () {
    for (final json in <Object?>[
      null,
      <Object?>[],
      {'server': 'https://books.example.ts.net'},
      {'server': 3, 'device_id': null, 'tokens': null},
      {'server': '', 'device_id': null, 'tokens': null},
      {
        'server': 'https://books.example.ts.net',
        'device_id': 7,
        'tokens': null,
      },
      {
        'server': 'https://books.example.ts.net',
        'device_id': null,
        'tokens': {'session_token': 'session-1'},
      },
    ]) {
      expect(
        () => StoredConnection.fromJson(json),
        throwsFormatException,
        reason: '$json',
      );
    }
  });
}
