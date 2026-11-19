import 'dart:async';

import 'package:bookserver/data/api_client.dart';
import 'package:bookserver/data/catalog_store.dart';
import 'package:bookserver/data/locales_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/data/settings_api.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

/// The language the app shows: the user's [setting] while the server offers it; else the first of
/// the [device]'s languages the server offers; else the server's default, else its first language.
/// `null` when it offers none.
// Not Flutter's basicLocaleListResolution: it also matches by region alone, which would show a
// French-speaking Swiss device German.
String? pickLanguage(
  List<OfferedLanguage> offered, {
  String? setting,
  List<Locale> device = const [],
}) {
  final codes = [for (final language in offered) language.code];
  if (codes.contains(setting)) {
    return setting;
  }
  for (final locale in device) {
    if (_codeFor(locale, codes) case final code?) {
      return code;
    }
  }
  for (final language in offered) {
    if (language.isDefault) {
      return language.code;
    }
  }
  return codes.firstOrNull;
}

/// The one of [codes] for [locale]: the same language and region (`pt-BR`), else the language
/// alone (`de` for `de-AT`), else the first code of the same language (`pt-BR` for `pt-PT`).
String? _codeFor(Locale locale, List<String> codes) {
  final language = locale.languageCode;
  final region = locale.countryCode;
  if (region != null && codes.contains('$language-$region')) {
    return '$language-$region';
  }
  if (codes.contains(language)) {
    return language;
  }
  return codes.where((code) => code.split('-').first == language).firstOrNull;
}

/// The catalog every screen shows: the built-in English, or the one kept from the session's
/// server, until the server's catalog in the picked language arrives.
class CatalogController extends ChangeNotifier {
  CatalogController({
    required this._builtIn,
    required this._store,
    required this._client,
    required this._session,
    this._deviceLocales = _platformLocales,
  });

  final Catalog _builtIn;
  final CatalogStore _store;
  final http.Client _client;
  final SessionController _session;
  final List<Locale> Function() _deviceLocales;

  Catalog? _fromServer;

  /// What [_fromServer] was made from: its server, language and ETag.
  StoredCatalog? _shown;
  (Uri?, bool)? _followed;
  var _picks = 0;

  Catalog get catalog => _fromServer ?? _builtIn;

  /// Shows the catalog kept from the session's server, then picks the language for where the
  /// session stands, and again whenever its server or sign-in changes. Nothing here waits for the
  /// server's answers.
  Future<void> load() async {
    final kept = await _store.read();
    if (kept != null && kept.server == _where.$1) {
      try {
        _show(kept);
      } on FormatException {
        // Broken texts: the server's next answer replaces them.
      }
    }
    _session.addListener(_follow);
    _follow();
  }

  @override
  void dispose() {
    _session.removeListener(_follow);
    // Overtakes a pick still waiting for the server, which would notify after the disposal.
    _picks++;
    super.dispose();
  }

  /// The session's server, and whether someone is signed in to it.
  (Uri?, bool) get _where => switch (_session.stage) {
    NeedsServer() => (null, false),
    LoggedOut(:final server) => (server, false),
    LoggedIn(:final server) => (server, true),
  };

  void _follow() {
    final now = _where;
    if (now == _followed) {
      return;
    }
    _followed = now;
    unawaited(_pick(now));
  }

  /// Fetches the catalog in the language picked for [server]. A pick a newer one overtook drops
  /// what it gets, and any failure keeps the catalog on screen.
  Future<void> _pick((Uri?, bool) where) async {
    final pick = ++_picks;
    final (server, signedIn) = where;
    if (server == null) {
      return;
    }
    try {
      final locales = LocalesApi(ApiClient(_client, server));
      final offered = await locales.languages();
      final setting = signedIn
          ? await _session.authorized(
              (api, token) => SettingsApi(api).language(token),
            )
          : null;
      final language = pickLanguage(
        offered,
        setting: setting,
        device: _deviceLocales(),
      );
      if (language == null || pick != _picks) {
        return;
      }
      final shown = _shown;
      final answer = await locales.texts(
        language,
        etag: shown?.server == server && shown?.language == language
            ? shown?.etag
            : null,
      );
      if (pick != _picks) {
        return;
      }
      if (answer case CatalogTexts(:final texts, :final etag)) {
        final record = StoredCatalog(
          server: server,
          language: language,
          etag: etag,
          texts: texts,
        );
        _show(record);
        await _store.write(record);
      }
    } on Exception {
      // No connection, a refusal, a broken answer or a full disk: the next start, or the next
      // change of server or sign-in, tries again.
    }
  }

  void _show(StoredCatalog record) {
    _fromServer = Catalog.fromJson(
      record.texts,
      language: record.language,
      fallback: _builtIn,
    );
    _shown = record;
    notifyListeners();
  }
}

List<Locale> _platformLocales() =>
    WidgetsBinding.instance.platformDispatcher.locales;
