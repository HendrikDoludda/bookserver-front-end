import 'dart:async';

import 'package:bookserver/data/api_client.dart';
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

/// The catalog every screen shows: the built-in English until the server's catalog in the picked
/// language arrives.
class CatalogController extends ChangeNotifier {
  CatalogController({
    required this._builtIn,
    required this._client,
    required this._session,
    this._deviceLocales = _platformLocales,
  });

  final Catalog _builtIn;
  final http.Client _client;
  final SessionController _session;
  final List<Locale> Function() _deviceLocales;

  Catalog? _fromServer;
  (Uri?, bool)? _followed;
  var _picks = 0;

  Catalog get catalog => _fromServer ?? _builtIn;

  /// Picks the language for where the session stands, and again whenever its server or sign-in
  /// changes. The server's answers arrive later; nothing here waits for them.
  void load() {
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

  void _follow() {
    final now = switch (_session.stage) {
      NeedsServer() => (null, false),
      LoggedOut(:final server) => (server, false),
      LoggedIn(:final server) => (server, true),
    };
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
      final texts = await locales.texts(language);
      if (pick != _picks) {
        return;
      }
      _fromServer = Catalog.fromJson(
        texts,
        language: language,
        fallback: _builtIn,
      );
      notifyListeners();
    } on Exception {
      // No connection, a refusal or a broken answer: the next change of server or sign-in tries
      // again.
    }
  }
}

List<Locale> _platformLocales() =>
    WidgetsBinding.instance.platformDispatcher.locales;
