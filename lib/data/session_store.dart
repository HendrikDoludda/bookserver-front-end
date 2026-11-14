import 'dart:convert';

import 'package:bookserver/data/session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the app keeps its [StoredConnection] between launches.
abstract interface class SessionStore {
  Future<StoredConnection?> read();

  Future<void> write(StoredConnection connection);

  Future<void> delete();
}

/// Keeps the connection in the platform's secure storage: the Keychain on iOS and macOS, a store
/// encrypted with a key from the Android Keystore on Android.
class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? _platformStorage;

  // macOS's default data-protection keychain needs a provisioning profile, and a free Apple
  // account's profile ties the app to the Mac that built it.
  static const _platformStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  static const _key = 'connection';

  final FlutterSecureStorage _storage;

  /// The stored connection; an unreadable one is deleted and counts as none.
  @override
  Future<StoredConnection?> read() async {
    try {
      final text = await _storage.read(key: _key);
      return text == null ? null : StoredConnection.fromJson(jsonDecode(text));
    } on FormatException {
      await delete();
    } on PlatformException {
      await delete();
    }
    return null;
  }

  @override
  Future<void> write(StoredConnection connection) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(connection.toJson()));
    } on PlatformException catch (error) {
      // The running app keeps its session in memory; only the next launch has to sign in again.
      debugPrint('Secure storage refused the session: ${error.code}');
    }
  }

  @override
  Future<void> delete() async {
    try {
      await _storage.delete(key: _key);
    } on PlatformException {
      // Whatever is left gets overwritten by the next write.
    }
  }
}
