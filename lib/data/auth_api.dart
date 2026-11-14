import 'package:bookserver/data/api_client.dart';

/// A session's tokens, as login and refresh answer them.
class SessionTokens {
  const SessionTokens({
    required this.sessionToken,
    required this.sessionExpiresAt,
    required this.refreshToken,
    required this.refreshExpiresAt,
    required this.deviceId,
  });

  factory SessionTokens.fromJson(Object? json) {
    if (json case {
      'session_token': String sessionToken,
      'session_expires_at': int sessionExpiresAt,
      'refresh_token': String refreshToken,
      'refresh_expires_at': int refreshExpiresAt,
      'device_id': String deviceId,
    }) {
      return SessionTokens(
        sessionToken: sessionToken,
        sessionExpiresAt: _fromUnixSeconds(sessionExpiresAt),
        refreshToken: refreshToken,
        refreshExpiresAt: _fromUnixSeconds(refreshExpiresAt),
        deviceId: deviceId,
      );
    }
    throw const FormatException('Not a session.');
  }

  final String sessionToken;
  final DateTime sessionExpiresAt;
  final String refreshToken;
  final DateTime refreshExpiresAt;
  final String deviceId;
}

/// What a correct password leads to.
sealed class LoginResult {
  const LoginResult();
}

final class LoginOk extends LoginResult {
  const LoginOk(this.tokens);

  final SessionTokens tokens;
}

final class LoginTotpRequired extends LoginResult {
  const LoginTotpRequired({
    required this.challengeToken,
    required this.challengeExpiresAt,
  });

  final String challengeToken;
  final DateTime challengeExpiresAt;
}

/// The server's health check and its `/api/v1/auth/…` session routes.
class AuthApi {
  AuthApi(this._client);

  final ApiClient _client;

  /// Whether a book server answers at the client's origin. No answer at all throws a
  /// [ConnectionException].
  Future<bool> isBookserver() async {
    try {
      return (await _client.getText('/health')).trim() == 'pong';
    } on ApiException {
      return false;
    } on FormatException {
      return false;
    }
  }

  Future<LoginResult> logIn({
    required String usernameOrEmail,
    required String password,
    required String deviceName,
    required String platform,
    String? deviceId,
  }) async {
    final json = await _client.postJson(
      '/api/v1/auth/login',
      body: {
        'username_or_email': usernameOrEmail,
        'password': password,
        'device_name': deviceName,
        'platform': platform,
        'device_id': ?deviceId,
      },
    );
    return switch (json) {
      {'status': 'ok'} => LoginOk(SessionTokens.fromJson(json)),
      {
        'status': 'totp_required',
        'challenge_token': String challengeToken,
        'challenge_expires_at': int challengeExpiresAt,
      } =>
        LoginTotpRequired(
          challengeToken: challengeToken,
          challengeExpiresAt: _fromUnixSeconds(challengeExpiresAt),
        ),
      _ => throw const FormatException('Not a login answer.'),
    };
  }

  /// New tokens for the session behind [refreshToken]; the old ones stop working.
  Future<SessionTokens> refresh(String refreshToken) async {
    final json = await _client.postJson(
      '/api/v1/auth/refresh',
      bearer: refreshToken,
    );
    return SessionTokens.fromJson(json);
  }

  /// Ends the session behind [token], its session or its refresh token.
  Future<void> logOut(String token) async {
    await _client.postJson('/api/v1/auth/logout', bearer: token);
  }
}

DateTime _fromUnixSeconds(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
