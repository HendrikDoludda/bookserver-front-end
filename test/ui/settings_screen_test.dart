import 'dart:convert';

import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../support/fake_server.dart';
import '../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });

  late _SettingsServer server;
  setUp(() => server = _SettingsServer());

  /// Starts signed in on the libraries and opens the settings with the top bar's button.
  Future<void> atSettings(
    WidgetTester tester, {
    bool followCatalog = false,
  }) async {
    await pumpApp(
      tester,
      catalog: english,
      store: signedInStore(),
      server: server.fake,
      followCatalog: followCatalog,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(english.text('home.settings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  }

  String? chosen(WidgetTester tester) => tester
      .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
      .groupValue;

  Map<String, Object?> lastPut() => jsonDecode(
    server.fake.requests.lastWhere((request) => request.method == 'PUT').body,
  ) as Map<String, Object?>;

  testWidgets('lists the device language, then each language with its icon', (
    tester,
  ) async {
    await atSettings(tester);

    expect(find.text(english.text('settings.language')), findsOneWidget);
    expect(find.text(english.text('settings.device_language')), findsOneWidget);
    expect(
      find.text(english.text('settings.device_language_explanation')),
      findsOneWidget,
    );
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Deutsch'), findsOneWidget);
    expect(find.text('🥨'), findsOneWidget);
    expect(find.byType(RadioListTile<String>), findsNWidgets(3));
  });

  testWidgets('marks the device language while none is chosen', (tester) async {
    await atSettings(tester);

    expect(chosen(tester), isEmpty);
  });

  testWidgets('marks the language the user chose', (tester) async {
    server.setting = 'de';
    await atSettings(tester);

    expect(chosen(tester), 'de');
  });

  testWidgets('a language chosen is saved, and the app shows it at once', (
    tester,
  ) async {
    await atSettings(tester, followCatalog: true);
    expect(find.text(english.text('settings.title')), findsOneWidget);

    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();

    expect(lastPut(), {'locale': 'de'});
    expect(chosen(tester), 'de');
    expect(find.text('Einstellungen'), findsOneWidget);
  });

  testWidgets('the device language is saved as no choice', (tester) async {
    server.setting = 'de';
    await atSettings(tester);

    await tester.tap(find.text(english.text('settings.device_language')));
    await tester.pumpAndSettle();

    expect(lastPut(), {'locale': null});
    expect(chosen(tester), isEmpty);
  });

  testWidgets('a refusal keeps the choice before and says why', (tester) async {
    server.putAnswer = jsonAnswer({'error': 'invalid_locale'}, 400);
    await atSettings(tester);

    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();

    expect(find.text(english.text('errors.invalid_locale')), findsOneWidget);
    expect(chosen(tester), isEmpty);
  });

  testWidgets('says why the settings did not load, with Reload', (
    tester,
  ) async {
    server.settingsFailures = 1;
    await atSettings(tester);

    expect(find.text(english.text('errors.internal_error')), findsOneWidget);
    await tester.tap(find.text(english.text('settings.reload')));
    await tester.pumpAndSettle();

    expect(find.text(english.text('errors.internal_error')), findsNothing);
    expect(find.text('Deutsch'), findsOneWidget);
  });

  group('the device-language entry', () {
    void deviceSpeaks(WidgetTester tester, Locale locale) {
      tester.platformDispatcher.localesTestValue = [locale];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    }

    bool askedForGerman() => server.fake.requests.any(
      (request) => request.url.path == '/api/v1/locales/de/translations',
    );

    testWidgets("is written in the device's language", (tester) async {
      deviceSpeaks(tester, const Locale('de'));
      await atSettings(tester);

      expect(find.text('Gerätesprache'), findsOneWidget);
      expect(find.text('Folgt der Sprache deines Geräts.'), findsOneWidget);
      expect(
        find.text(english.text('settings.title')),
        findsOneWidget,
        reason: 'the rest stays in the language on screen',
      );
    });

    testWidgets(
      "is written in the server's default when it lacks the device's language",
      (tester) async {
        deviceSpeaks(tester, const Locale('fr'));
        await atSettings(tester);

        expect(
          find.text(english.text('settings.device_language')),
          findsOneWidget,
        );
        expect(askedForGerman(), isFalse);
      },
    );

    testWidgets('stays in the device language after another is chosen', (
      tester,
    ) async {
      await atSettings(tester, followCatalog: true);

      await tester.tap(find.text('Deutsch'));
      await tester.pumpAndSettle();

      expect(find.text('Einstellungen'), findsOneWidget);
      expect(
        find.text(english.text('settings.device_language')),
        findsOneWidget,
      );
      expect(find.text('Gerätesprache'), findsNothing);
    });

    testWidgets('is written in the language on screen when the server fails', (
      tester,
    ) async {
      deviceSpeaks(tester, const Locale('de'));
      server.germanFails = true;
      await atSettings(tester);

      expect(
        find.text(english.text('settings.device_language')),
        findsOneWidget,
      );
      expect(askedForGerman(), isTrue);
    });
  });
}

/// A server offering English, its default, and German with an icon, keeping the user's language
/// setting as a PUT leaves it.
class _SettingsServer {
  String? setting;

  /// Answers the next PUT in place of saving it.
  http.Response? putAnswer;

  /// How many reads of the settings fail before one works.
  var settingsFailures = 0;

  /// Whether the German texts fail to load.
  var germanFails = false;

  late final fake = bookServer(
    (request) async => switch ((request.method, request.url.path)) {
      ('GET', '/api/v1/libraries') => jsonAnswer([]),
      ('GET', '/api/v1/locales') => jsonAnswer([
        {
          'code': 'en',
          'display_name': 'English',
          'icon': null,
          'is_default': true,
        },
        {
          'code': 'de',
          'display_name': 'Deutsch',
          'icon': '🥨',
          'is_default': false,
        },
      ]),
      ('GET', '/api/v1/account/settings') => _read(),
      ('PUT', '/api/v1/account/settings') => putAnswer ?? _save(request),
      ('GET', '/api/v1/locales/de/translations') =>
        germanFails
            ? jsonAnswer({'error': 'internal_error'}, 500)
            : jsonAnswer({
                'settings': {
                  'title': 'Einstellungen',
                  'device_language': 'Gerätesprache',
                  'device_language_explanation':
                      'Folgt der Sprache deines Geräts.',
                },
              }),
      ('GET', '/api/v1/locales/en/translations') => jsonAnswer(
        <String, Object?>{},
      ),
      _ => notFound(),
    },
  );

  http.Response _read() {
    if (settingsFailures > 0) {
      settingsFailures--;
      return jsonAnswer({'error': 'internal_error'}, 500);
    }
    return jsonAnswer({'locale': setting});
  }

  http.Response _save(http.Request request) {
    setting = jsonDecode(request.body)['locale'] as String?;
    return jsonAnswer({'locale': setting});
  }
}
