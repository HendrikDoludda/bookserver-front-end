import 'package:bookserver/data/api_client.dart';

/// Whether two-factor authentication is on, and how many unused recovery codes are left.
class TwoFactorStatus {
  const TwoFactorStatus({
    required this.enabled,
    required this.recoveryCodesLeft,
  });

  final bool enabled;
  final int recoveryCodesLeft;
}

/// A setup waiting for its first code: what the authenticator app needs.
class TwoFactorSetup {
  const TwoFactorSetup({required this.otpauthUrl, required this.secret});

  /// The `otpauth://` link the QR code holds.
  final String otpauthUrl;

  /// The same secret as text, to type into the authenticator app.
  final String secret;
}

/// The signed-in user's two-factor authentication: `/api/v1/account/totp…`.
class TwoFactorApi {
  TwoFactorApi(this._client);

  final ApiClient _client;

  Future<TwoFactorStatus> status(String sessionToken) async {
    final json = await _client.getJson(
      '/api/v1/account/totp',
      bearer: sessionToken,
    );
    if (json case {
      'enabled': bool enabled,
      'recovery_codes_left': int recoveryCodesLeft,
    }) {
      return TwoFactorStatus(
        enabled: enabled,
        recoveryCodesLeft: recoveryCodesLeft,
      );
    }
    throw const FormatException('Not a two-factor status.');
  }

  /// Starts a setup; it is on only once [confirm] took a code from the app.
  Future<TwoFactorSetup> start(String sessionToken) async {
    final json = await _client.postJson(
      '/api/v1/account/totp',
      bearer: sessionToken,
    );
    if (json case {
      'otpauth_url': String otpauthUrl,
      'secret_base32': String secret,
    }) {
      return TwoFactorSetup(otpauthUrl: otpauthUrl, secret: secret);
    }
    throw const FormatException('Not a two-factor setup.');
  }

  /// Turns the setup on with a [code] from the app and the [password]; answers the recovery
  /// codes, which the server shows only this once.
  Future<List<String>> confirm(
    String sessionToken, {
    required String code,
    required String password,
  }) async => _codes(
    await _client.postJson(
      '/api/v1/account/totp/confirm',
      body: {'code': code, 'password': password},
      bearer: sessionToken,
    ),
  );

  /// Turns two-factor authentication off; the server ends every session of the user, this one
  /// too. [code] is from the app or one of the recovery codes.
  Future<void> disable(
    String sessionToken, {
    required String password,
    required String code,
  }) async {
    await _client.postJson(
      '/api/v1/account/totp/disable',
      body: {'password': password, 'code': code},
      bearer: sessionToken,
    );
  }

  /// Replaces the recovery codes; answers the new ones, shown only this once. [code] is from the
  /// app or one of the recovery codes.
  Future<List<String>> renewRecoveryCodes(
    String sessionToken, {
    required String password,
    required String code,
  }) async => _codes(
    await _client.postJson(
      '/api/v1/account/totp/recovery_codes',
      body: {'password': password, 'code': code},
      bearer: sessionToken,
    ),
  );

  static List<String> _codes(Object? json) {
    if (json case {'recovery_codes': List<Object?> codes}
        when codes.every((code) => code is String)) {
      return codes.cast<String>();
    }
    throw const FormatException('Not a list of recovery codes.');
  }
}
