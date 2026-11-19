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

  Map<String, Object?> toJson() => {
    'session_token': sessionToken,
    'session_expires_at': _toUnixSeconds(sessionExpiresAt),
    'refresh_token': refreshToken,
    'refresh_expires_at': _toUnixSeconds(refreshExpiresAt),
    'device_id': deviceId,
  };

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

/// What a sign-up leads to.
sealed class SignUpResult {
  const SignUpResult();
}

/// The account is ready and signed in: the server sends no mail, or it is the first account.
final class SignedUp extends SignUpResult {
  const SignedUp(this.tokens);

  final SessionTokens tokens;
}

/// The account waits for the code the server mailed.
final class VerificationRequired extends SignUpResult {
  const VerificationRequired();
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
    return _loginResult(json);
  }

  /// Creates an account. [setupCode] is needed only for the server's first account, and
  /// [locale] becomes the account's language setting.
  Future<SignUpResult> signUp({
    required String email,
    required String username,
    required String password,
    required String passwordRepeat,
    required String deviceName,
    required String platform,
    String? deviceId,
    String? setupCode,
    String? locale,
  }) async {
    final json = await _client.postJson(
      '/api/v1/auth/register',
      body: {
        'email': email,
        'username': username,
        'password': password,
        'password_repeat': passwordRepeat,
        'device_name': deviceName,
        'platform': platform,
        'device_id': ?deviceId,
        'setup_code': ?setupCode,
        'locale': ?locale,
      },
    );
    return switch (json) {
      {'status': 'ok'} => SignedUp(SessionTokens.fromJson(json)),
      {'verification_required': true} => const VerificationRequired(),
      _ => throw const FormatException('Not a sign-up answer.'),
    };
  }

  /// Confirms the account's email address with the mailed [code], and signs in like [logIn].
  Future<LoginResult> verifyEmail({
    required String usernameOrEmail,
    required String password,
    required String code,
    required String deviceName,
    required String platform,
    String? deviceId,
  }) async {
    final json = await _client.postJson(
      '/api/v1/auth/verify_email',
      body: {
        'username_or_email': usernameOrEmail,
        'password': password,
        'code': code,
        'device_name': deviceName,
        'platform': platform,
        'device_id': ?deviceId,
      },
    );
    return _loginResult(json);
  }

  /// Asks for a new code for an account that waits for its email confirmation. The answer is
  /// the same whether or not such an account exists.
  Future<void> resendVerification(String usernameOrEmail) async {
    await _client.postJson(
      '/api/v1/auth/verify_email/resend',
      body: {'username_or_email': usernameOrEmail},
    );
  }

  /// Finishes a login that answered [LoginTotpRequired], with a code from the authenticator app
  /// or, when [recoveryCode], one of the recovery codes.
  Future<SessionTokens> logInWithCode(
    String challengeToken,
    String code, {
    required bool recoveryCode,
  }) async {
    final json = await _client.postJson(
      recoveryCode
          ? '/api/v1/auth/login/recovery_code'
          : '/api/v1/auth/login/totp',
      body: {'code': code},
      bearer: challengeToken,
    );
    if (json case {'status': 'ok'}) {
      return SessionTokens.fromJson(json);
    }
    throw const FormatException('Not a login answer.');
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

/// Login's answer, which the email verification gives as well.
LoginResult _loginResult(Object? json) => switch (json) {
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

DateTime _fromUnixSeconds(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

int _toUnixSeconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;
