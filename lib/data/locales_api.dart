import 'dart:convert';

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

  /// The texts of the language [code], or [CatalogUnchanged] while they are still the ones [etag]
  /// names.
  Future<CatalogAnswer> texts(String code, {String? etag}) async {
    final response = await _client.revalidate(
      '/api/v1/locales/${Uri.encodeComponent(code)}/translations',
      etag: etag,
    );
    if (response.statusCode == 304) {
      return const CatalogUnchanged();
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map<String, Object?>) {
      throw const FormatException('A catalog is an object of namespaces.');
    }
    return CatalogTexts(json, etag: response.headers['etag']);
  }
}

/// What the server answers when asked for a language's texts.
sealed class CatalogAnswer {
  const CatalogAnswer();
}

/// The texts are still the ones the ETag sent along names.
final class CatalogUnchanged extends CatalogAnswer {
  const CatalogUnchanged();
}

final class CatalogTexts extends CatalogAnswer {
  const CatalogTexts(this.texts, {required this.etag});

  /// By namespace, as `Catalog.fromJson` reads them.
  final Map<String, Object?> texts;

  /// The server's ETag for [texts], or `null` when it sent none.
  final String? etag;
}
