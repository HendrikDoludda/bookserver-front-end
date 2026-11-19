import 'package:bookserver/data/api_client.dart';

/// A language the server offers, as `GET /api/v1/locales` lists it.
class OfferedLanguage {
  const OfferedLanguage({required this.code, required this.isDefault});

  /// Such as `de` or `pt-BR`.
  final String code;

  /// Whether the server shows it when nothing else picks a language.
  final bool isDefault;
}

/// The server's translation catalog: the languages it offers and each one's texts. Neither needs a
/// session, since the login screen needs its texts before anyone has signed in.
class LocalesApi {
  LocalesApi(this._client);

  final ApiClient _client;

  /// The languages, in the server's order.
  Future<List<OfferedLanguage>> languages() async {
    final json = await _client.getJson('/api/v1/locales');
    if (json is! List<Object?>) {
      throw const FormatException('Not a list of languages.');
    }
    return [
      for (final entry in json)
        switch (entry) {
          {'code': String code, 'is_default': bool isDefault} =>
            OfferedLanguage(code: code, isDefault: isDefault),
          _ => throw const FormatException('Not a language.'),
        },
    ];
  }

  /// The texts of the language [code] by namespace, as `Catalog.fromJson` reads them.
  Future<Object?> texts(String code) => _client.getJson(
    '/api/v1/locales/${Uri.encodeComponent(code)}/translations',
  );
}
