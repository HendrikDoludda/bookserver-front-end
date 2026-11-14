import 'dart:io' show Platform;

import 'package:bookserver/data/api_client.dart';
import 'package:bookserver/data/auth_api.dart';
import 'package:bookserver/data/server_address.dart';
import 'package:bookserver/data/session.dart';
import 'package:bookserver/data/session_store.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Where the app stands with its server; the root shows one screen for each.
sealed class SessionStage {
  const SessionStage();
}

final class NeedsServer extends SessionStage {
  const NeedsServer();
}

final class LoggedOut extends SessionStage {
  const LoggedOut(this.server, {this.endedKey});

  final Uri server;

  /// When the server ended the session: the text key that says so.
  final String? endedKey;
}

final class LoggedIn extends SessionStage {
  const LoggedIn(this.server);

  final Uri server;
}

/// No session is left for a call; the app is back at the login screen.
class SessionEndedException implements Exception {
  const SessionEndedException();

  @override
  String toString() => 'SessionEndedException';
}

/// The app's connection to its server: its stage, signing in and out, and the session token
/// that every call needing a session gets through [authorized].
class SessionController extends ChangeNotifier {
  SessionController({
    required this._store,
    required this._client,
    this._clock = DateTime.now,
    this._allowHttp = kDebugMode,
    String? platform,
  }) : _platform = platform ?? Platform.operatingSystem;

  // A minute's margin, so a token doesn't run out on its way to the server.
  static const _refreshMargin = Duration(minutes: 1);
  static const _sessionEndedKey = 'errors.unauthorized';

  final SessionStore _store;
  final http.Client _client;
  final DateTime Function() _clock;
  final bool _allowHttp;
  final String _platform;

  StoredConnection? _connection;
  SessionStage _stage = const NeedsServer();
  Future<SessionTokens>? _refreshing;

  SessionStage get stage => _stage;

  /// Takes up what the app kept from its last run.
  Future<void> load() async {
    final connection = await _store.read();
    _connection = connection;
    _show(switch (connection) {
      null => const NeedsServer(),
      StoredConnection(:final server, tokens: null) => LoggedOut(server),
      StoredConnection(:final server) => LoggedIn(server),
    });
  }

  /// Checks the typed address and keeps it in place of any earlier server. Throws an
  /// [AddressException] when it isn't a book server's address, a [ConnectionException] when
  /// nothing answers.
  Future<void> useServer(String typed) async {
    final server = parseServerAddress(typed, allowHttp: _allowHttp);
    if (!await _auth(server).isBookserver()) {
      throw const AddressException(AddressProblem.notABookserver);
    }
    await _save(StoredConnection(server: server));
    _show(LoggedOut(server));
  }

  Future<LoginResult> logIn(String usernameOrEmail, String password) async {
    final connection =
        _connection ?? (throw StateError('No server to log in to.'));
    final result = await _auth(connection.server).logIn(
      usernameOrEmail: usernameOrEmail,
      password: password,
      deviceName: _deviceName,
      platform: _platform,
      deviceId: connection.deviceId,
    );
    if (result case LoginOk(:final tokens)) {
      await _save(connection.withTokens(tokens));
      _show(LoggedIn(connection.server));
    }
    return result;
  }

  /// Signs out here at once, then tells the server.
  Future<void> logOut() async {
    final connection = _connection;
    final tokens = connection?.tokens;
    if (connection == null || tokens == null) {
      return;
    }
    await _save(connection.withoutTokens());
    _show(LoggedOut(connection.server));
    await _endOnServer(connection.server, tokens);
  }

  /// Forgets the server, so the app asks for one again.
  Future<void> forgetServer() async {
    _connection = null;
    await _store.delete();
    _show(const NeedsServer());
  }

  /// Runs [call] with a live session token: refreshed first when it's about to run out, and
  /// once more when the server answers 401. Throws [SessionEndedException] once the session
  /// is over.
  Future<T> authorized<T>(
    Future<T> Function(ApiClient api, String sessionToken) call,
  ) async {
    var (server, tokens) = _session();
    if (tokens.sessionExpiresAt.difference(_clock()) < _refreshMargin) {
      tokens = await _freshTokens(tokens);
    }
    final api = ApiClient(_client, server);
    try {
      return await call(api, tokens.sessionToken);
    } on ApiException catch (error) {
      if (error.status != 401) {
        rethrow;
      }
    }
    final retryWith = await _freshTokens(tokens);
    try {
      return await call(api, retryWith.sessionToken);
    } on ApiException catch (error) {
      if (error.status != 401) {
        rethrow;
      }
      await _end(retryWith);
      throw const SessionEndedException();
    }
  }

  /// Tokens newer than [used]: the running refresh's, those another call already got, or a
  /// new refresh's — never two refreshes at once, since the server lets only the first through.
  Future<SessionTokens> _freshTokens(SessionTokens used) async {
    final running = _refreshing;
    if (running != null) {
      return running;
    }
    final (_, current) = _session();
    if (!identical(current, used)) {
      return current;
    }
    return _refreshing = _refresh(used).whenComplete(() => _refreshing = null);
  }

  Future<SessionTokens> _refresh(SessionTokens used) async {
    final (server, _) = _session();
    final SessionTokens tokens;
    try {
      tokens = await _auth(server).refresh(used.refreshToken);
    } on ApiException catch (error) {
      if (error.status != 401) {
        rethrow;
      }
      await _end(used);
      throw const SessionEndedException();
    }
    final connection = _connection;
    if (connection == null || !identical(connection.tokens, used)) {
      // Signed out while this refresh was on its way: end the session it renewed, too.
      await _endOnServer(server, tokens);
      throw const SessionEndedException();
    }
    await _save(connection.withTokens(tokens));
    return tokens;
  }

  /// Ends the session the server refused, unless the user has signed out in the meantime.
  Future<void> _end(SessionTokens refused) async {
    final connection = _connection;
    if (connection == null || !identical(connection.tokens, refused)) {
      return;
    }
    await _save(connection.withoutTokens());
    _show(LoggedOut(connection.server, endedKey: _sessionEndedKey));
  }

  Future<void> _endOnServer(Uri server, SessionTokens tokens) async {
    try {
      await _auth(server).logOut(tokens.refreshToken);
    } on Exception {
      // Signed out here either way; a session the server keeps runs out with its refresh token.
    }
  }

  (Uri, SessionTokens) _session() {
    if (_connection case StoredConnection(:final server, :final tokens?)) {
      return (server, tokens);
    }
    throw const SessionEndedException();
  }

  Future<void> _save(StoredConnection connection) async {
    _connection = connection;
    await _store.write(connection);
  }

  void _show(SessionStage stage) {
    _stage = stage;
    notifyListeners();
  }

  AuthApi _auth(Uri server) => AuthApi(ApiClient(_client, server));

  String get _deviceName => switch (_platform) {
    'ios' => 'iOS',
    'android' => 'Android',
    'macos' => 'macOS',
    'windows' => 'Windows',
    'linux' => 'Linux',
    _ => _platform,
  };
}
