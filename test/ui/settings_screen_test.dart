import 'dart:convert';

import 'package:bookserver/data/preferences.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/code_and_password_screen.dart';
import 'package:bookserver/ui/qr_code.dart';
import 'package:bookserver/ui/recovery_codes_screen.dart';
import 'package:bookserver/ui/settings_screen.dart';
import 'package:bookserver/ui/two_factor_setup_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../support/fake_server.dart';
import '../support/memory_preferences_store.dart';
import '../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });

  late _SettingsServer server;
  setUp(() => server = _SettingsServer());

  /// Starts signed in on the libraries and opens the settings from the user menu.
  Future<void> atSettings(
    WidgetTester tester, {
    bool followCatalog = false,
    PreferencesController? preferences,
  }) async {
    await pumpApp(
      tester,
      catalog: english,
      store: signedInStore(),
      server: server.fake,
      followCatalog: followCatalog,
      preferences: preferences,
    );
    await tester.pumpAndSettle();
    await chooseInUserMenu(tester, english, 'menu.settings');
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

  group('two-factor authentication', () {
    Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> enter(WidgetTester tester, String labelKey, String text) =>
        tester.enterText(
          find.widgetWithText(TextField, english.text(labelKey)),
          text,
        );

    Finder filledButton(String key) =>
        find.widgetWithText(FilledButton, english.text(key));

    Map<String, Object?> bodyOf(String path) => jsonDecode(
      server.fake.requests.lastWhere((r) => r.url.path == path).body,
    ) as Map<String, Object?>;

    testWidgets('off: says so, with Turn on', (tester) async {
      await atSettings(tester);

      expect(find.text(english.text('two_factor.title')), findsOneWidget);
      expect(
        find.text(english.text('two_factor.explanation_off')),
        findsOneWidget,
      );
      expect(find.text(english.text('two_factor.turn_on')), findsOneWidget);
      expect(find.text(english.text('two_factor.on')), findsNothing);
    });

    testWidgets('on: says so, with the codes left and both ways on', (
      tester,
    ) async {
      server
        ..twoFactorOn = true
        ..codesLeft = 1;
      await atSettings(tester);

      expect(find.text(english.text('two_factor.on')), findsOneWidget);
      expect(
        find.text(english.plural('two_factor.codes_left', 1)),
        findsOneWidget,
      );
      expect(find.text(english.text('two_factor.renew')), findsOneWidget);
      expect(find.text(english.text('two_factor.turn_off')), findsOneWidget);
      expect(find.text(english.text('two_factor.turn_on')), findsNothing);
    });

    testWidgets(
      'turning on shows the QR code and the key, then the codes once, then on',
      (tester) async {
        await atSettings(tester);

        await tapAndSettle(
          tester,
          find.text(english.text('two_factor.turn_on')),
        );
        expect(find.byType(TwoFactorSetupScreen), findsOneWidget);
        expect(find.byType(QrCodeView), findsOneWidget);
        expect(find.text('JBSWY3DPEHPK3PXP'), findsOneWidget);

        await enter(tester, 'two_factor.code', '123456');
        await enter(tester, 'two_factor.password', 'correct horse battery');
        await tester.pump();
        await tapAndSettle(tester, filledButton('two_factor.confirm'));

        expect(bodyOf('/api/v1/account/totp/confirm'), {
          'code': '123456',
          'password': 'correct horse battery',
        });
        expect(find.byType(RecoveryCodesScreen), findsOneWidget);
        expect(find.textContaining('CODE-10-AAAA-BBBB'), findsOneWidget);
        expect(find.byType(BackButton), findsNothing);

        await tapAndSettle(tester, filledButton('two_factor.done'));

        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(find.text(english.text('two_factor.on')), findsOneWidget);
        expect(
          find.text(english.plural('two_factor.codes_left', 10)),
          findsOneWidget,
        );
      },
    );

    testWidgets('new recovery codes are shown once, then counted', (
      tester,
    ) async {
      server
        ..twoFactorOn = true
        ..codesLeft = 2;
      await atSettings(tester);

      await tapAndSettle(tester, find.text(english.text('two_factor.renew')));
      expect(find.byType(CodeAndPasswordScreen), findsOneWidget);
      await enter(tester, 'two_factor.password', 'correct horse battery');
      await enter(tester, 'two_factor.code_or_recovery', '123456');
      await tester.pump();
      await tapAndSettle(tester, filledButton('two_factor.renew'));

      expect(bodyOf('/api/v1/account/totp/recovery_codes'), {
        'password': 'correct horse battery',
        'code': '123456',
      });
      expect(find.byType(RecoveryCodesScreen), findsOneWidget);
      await tapAndSettle(tester, filledButton('two_factor.done'));

      expect(
        find.text(english.plural('two_factor.codes_left', 10)),
        findsOneWidget,
      );
    });

    testWidgets('turning off signs out to the login screen, which says why', (
      tester,
    ) async {
      server
        ..twoFactorOn = true
        ..codesLeft = 10;
      await atSettings(tester);

      await tapAndSettle(
        tester,
        find.text(english.text('two_factor.turn_off')),
      );
      await enter(tester, 'two_factor.password', 'correct horse battery');
      await enter(tester, 'two_factor.code_or_recovery', '123456');
      await tester.pump();
      await tapAndSettle(tester, filledButton('two_factor.turn_off'));

      expect(bodyOf('/api/v1/account/totp/disable'), {
        'password': 'correct horse battery',
        'code': '123456',
      });
      expect(
        find.text(english.text('login.username_or_email')),
        findsOneWidget,
      );
      expect(find.text(english.text('two_factor.off_done')), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
    });

    testWidgets('a wrong code says so and stays', (tester) async {
      server
        ..twoFactorOn = true
        ..codesLeft = 10;
      await atSettings(tester);
      await tapAndSettle(
        tester,
        find.text(english.text('two_factor.turn_off')),
      );

      await enter(tester, 'two_factor.password', 'correct horse battery');
      await enter(tester, 'two_factor.code_or_recovery', '000000');
      await tester.pump();
      await tapAndSettle(tester, filledButton('two_factor.turn_off'));

      expect(
        find.text(english.text('errors.invalid_or_expired_code')),
        findsOneWidget,
      );
      expect(find.byType(CodeAndPasswordScreen), findsOneWidget);
      expect(server.twoFactorOn, isTrue);
    });
  });

  group('handedness', () {
    void onPlatform(TargetPlatform platform) {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
    }

    Finder heading() => find.text(english.text('settings.handedness'));

    /// The handedness choice, scrolled into view: it is the last thing on the screen.
    Future<Set<Handedness>> shown(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.byType(SegmentedButton<Handedness>),
        100,
        scrollable: find
            .descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      // The scroll lands in the next frame; a tap before it aims at the old place.
      await tester.pumpAndSettle();
      return tester
          .widget<SegmentedButton<Handedness>>(
            find.byType(SegmentedButton<Handedness>),
          )
          .selected;
    }

    Future<void> chooseLeft(WidgetTester tester) async {
      await shown(tester);
      await tester.tap(find.text(english.text('settings.left_handed')));
      await tester.pumpAndSettle();
    }

    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets(
        'on ${platform.name}: right-handed until left is chosen, which the device keeps',
        (tester) async {
          onPlatform(platform);
          final store = MemoryPreferencesStore();
          final preferences = PreferencesController(store: store);
          await atSettings(tester, preferences: preferences);

          expect(await shown(tester), {Handedness.right});
          expect(heading(), findsOneWidget);

          await chooseLeft(tester);

          expect(await shown(tester), {Handedness.left});
          expect(preferences.preferences.handedness, Handedness.left);
          expect(store.preferences?.handedness, Handedness.left);
          expect(
            server.fake.requests.where((request) => request.method == 'PUT'),
            isEmpty,
            reason: 'kept on the device, not on the server',
          );
        },
      );
    }

    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      testWidgets('not on ${platform.name}', (tester) async {
        onPlatform(platform);
        await atSettings(tester);

        expect(heading(), findsNothing);
        expect(find.byType(SegmentedButton<Handedness>), findsNothing);
      });
    }

    testWidgets('the choice outlasts signing out', (tester) async {
      final store = MemoryPreferencesStore();
      final preferences = PreferencesController(store: store);
      await atSettings(tester, preferences: preferences);
      await chooseLeft(tester);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await chooseInUserMenu(tester, english, 'menu.sign_out');
      await tester.pumpAndSettle();

      expect(
        find.text(english.text('login.username_or_email')),
        findsOneWidget,
      );
      expect(preferences.preferences.handedness, Handedness.left);
      expect(store.preferences?.handedness, Handedness.left);
    });
  });
}

const twoFactorSetupUrl =
    'otpauth://totp/Bookserver:alice?secret=JBSWY3DPEHPK3PXP&issuer=Bookserver';

/// A server offering English, its default, and German with an icon, keeping the user's language
/// setting as a PUT leaves it, and two-factor authentication as its routes leave it: the app code
/// `123456` and the password `correct horse battery` are the right ones.
class _SettingsServer {
  String? setting;

  /// Answers the next PUT in place of saving it.
  http.Response? putAnswer;

  /// How many reads of the settings fail before one works.
  var settingsFailures = 0;

  /// Whether the German texts fail to load.
  var germanFails = false;

  var twoFactorOn = false;
  var codesLeft = 0;
  var _issued = 0;

  http.Response _twoFactor(http.Request request) {
    final body = request.body.isEmpty
        ? const <String, Object?>{}
        : jsonDecode(request.body) as Map<String, Object?>;
    if (body.isNotEmpty &&
        (body['code'] != '123456' ||
            body['password'] != 'correct horse battery')) {
      return jsonAnswer({'error': 'invalid_or_expired_code'}, 400);
    }
    switch (request.url.path) {
      case '/api/v1/account/totp':
        return jsonAnswer({
          'otpauth_url': twoFactorSetupUrl,
          'secret_base32': 'JBSWY3DPEHPK3PXP',
        });
      case '/api/v1/account/totp/disable':
        twoFactorOn = false;
        return http.Response('', 204);
      default:
        twoFactorOn = true;
        codesLeft = 10;
        _issued++;
        return jsonAnswer({
          'recovery_codes': [
            for (var i = 0; i < 10; i++) 'CODE-$_issued$i-AAAA-BBBB',
          ],
        });
    }
  }

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
      ('GET', '/api/v1/account/totp') => jsonAnswer({
        'enabled': twoFactorOn,
        'recovery_codes_left': codesLeft,
      }),
      ('POST', final path) when path.startsWith('/api/v1/account/totp') =>
        _twoFactor(request),
      ('POST', '/api/v1/auth/logout') => http.Response('', 204),
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
