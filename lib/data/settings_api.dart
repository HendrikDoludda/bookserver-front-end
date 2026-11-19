import 'package:bookserver/data/api_client.dart';

/// The signed-in user's own settings.
class SettingsApi {
  SettingsApi(this._client);

  final ApiClient _client;

  /// The language code the user chose, or `null` while they haven't chosen one.
  Future<String?> language(String sessionToken) async {
    final json = await _client.getJson(
      '/api/v1/account/settings',
      bearer: sessionToken,
    );
    if (json case {'locale': final String? locale}) {
      return locale;
    }
    throw const FormatException('Not the settings.');
  }

  /// Makes [code] the user's language; `null` leaves the choice to each device.
  Future<void> setLanguage(String sessionToken, String? code) async {
    await _client.putJson(
      '/api/v1/account/settings',
      body: {'locale': code},
      bearer: sessionToken,
    );
  }
}
