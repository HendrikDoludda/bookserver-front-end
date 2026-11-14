import 'package:bookserver/data/auth_api.dart';
import 'package:bookserver/data/session.dart';
import 'package:bookserver/data/session_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final connection = StoredConnection(
    server: Uri.parse('https://books.example.ts.net'),
    deviceId: 'device-1',
    tokens: SessionTokens(
      sessionToken: 'session-1',
      sessionExpiresAt: DateTime.utc(2026, 11, 14, 12, 15),
      refreshToken: 'refresh-1',
      refreshExpiresAt: DateTime.utc(2026, 12, 14, 12),
      deviceId: 'device-1',
    ),
  );

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('keeps a connection from one read to the next', () async {
    await SecureSessionStore().write(connection);

    final stored = await SecureSessionStore().read();

    expect(stored?.toJson(), connection.toJson());
  });

  test('reads none when nothing is stored', () async {
    expect(await SecureSessionStore().read(), isNull);
  });

  test('an unreadable record is deleted and counts as none', () async {
    for (final stored in [
      'not json',
      '[]',
      '{"server": 3}',
      '{"server": "https://books.example.ts.net"}',
    ]) {
      FlutterSecureStorage.setMockInitialValues({'connection': stored});

      expect(await SecureSessionStore().read(), isNull, reason: stored);
      expect(
        await const FlutterSecureStorage().read(key: 'connection'),
        isNull,
        reason: stored,
      );
    }
  });

  test('delete removes the record', () async {
    await SecureSessionStore().write(connection);

    await SecureSessionStore().delete();

    expect(await SecureSessionStore().read(), isNull);
  });

  test(
    'a storage error reads as none, and a refused write throws nothing',
    () async {
      final store = SecureSessionStore(const _FailingStorage());

      expect(await store.read(), isNull);
      await store.write(connection);
    },
  );
}

/// A secure storage the platform refuses, like a keychain that's locked.
class _FailingStorage extends FlutterSecureStorage {
  const _FailingStorage();

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => Future.error(PlatformException(code: 'unreadable'));

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => Future.error(PlatformException(code: 'locked'));
}
