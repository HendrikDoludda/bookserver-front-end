import 'dart:convert';

import 'package:bookserver/data/session.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/sign_up_screen.dart';
import 'package:bookserver/ui/verify_email_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../support/fake_server.dart';
import '../support/memory_session_store.dart';
import '../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });

  /// A server whose sign-up answers with [signUp]; the verification signs in.
  FakeServer accountServer(http.Response Function(http.Request) signUp) =>
      bookServer(
        (request) async => switch (request.url.path) {
          '/api/v1/auth/register' => signUp(request),
          '/api/v1/auth/verify_email' => jsonAnswer({
            'status': 'ok',
            ...tokensJson(),
          }),
          '/api/v1/libraries' => jsonAnswer([]),
          '/api/v1/locales' => jsonAnswer([
            {
              'code': 'en',
              'display_name': 'English',
              'icon': null,
              'is_default': true,
            },
            {
              'code': 'de',
              'display_name': 'Deutsch',
              'icon': null,
              'is_default': false,
            },
          ]),
          '/api/v1/locales/de/translations' => jsonAnswer({
            'app': {'name': 'Bücherserver'},
          }),
          _ => notFound(),
        },
      );

  http.Response signedUp(http.Request _) =>
      jsonAnswer({'status': 'ok', ...tokensJson()});
  http.Response waitsForCode(http.Request _) =>
      jsonAnswer({'verification_required': true}, 202);

  Map<String, Object?> lastBody(FakeServer server, String path) =>
      jsonDecode(server.requests.lastWhere((r) => r.url.path == path).body)
          as Map<String, Object?>;

  Finder field(String key) => find.widgetWithText(TextField, english.text(key));
  Finder submitButton() =>
      find.widgetWithText(FilledButton, english.text('sign_up.submit'));

  /// Starts on the login screen of [server] and opens the sign-up from there.
  Future<SessionController> atSignUp(
    WidgetTester tester,
    FakeServer server, {
    bool followCatalog = false,
  }) async {
    final session = await pumpApp(
      tester,
      catalog: english,
      store: MemorySessionStore()
        ..connection = StoredConnection(server: testOrigin),
      server: server,
      followCatalog: followCatalog,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(english.text('login.create_account')));
    await tester.pumpAndSettle();
    expect(find.byType(SignUpScreen), findsOneWidget);
    return session;
  }

  Future<void> fillIn(WidgetTester tester) async {
    await tester.enterText(field('sign_up.email'), ' alice@example.com ');
    await tester.enterText(field('sign_up.username'), ' alice ');
    await tester.enterText(field('sign_up.password'), 'correct horse battery');
    await tester.enterText(
      field('sign_up.password_repeat'),
      'correct horse battery',
    );
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester) async {
    // Once the setup code and a message show, the button sits below the test window's edge.
    await tester.ensureVisible(submitButton());
    await tester.tap(submitButton());
    await tester.pumpAndSettle();
  }

  testWidgets('shows the rules for the name and the password', (tester) async {
    await atSignUp(tester, accountServer(signedUp));

    expect(find.text(english.text('sign_up.username_rule')), findsOneWidget);
    expect(find.text(english.text('sign_up.password_rule')), findsOneWidget);
    expect(field('sign_up.setup_code'), findsNothing);
  });

  testWidgets('the button waits for all four fields', (tester) async {
    await atSignUp(tester, accountServer(signedUp));
    FilledButton button() => tester.widget<FilledButton>(submitButton());

    expect(button().onPressed, isNull);
    await fillIn(tester);
    expect(button().onPressed, isNotNull);
  });

  testWidgets('an account ready at once signs in', (tester) async {
    final server = accountServer(signedUp);
    final session = await atSignUp(tester, server);

    await fillIn(tester);
    await submit(tester);

    expect(session.stage, isA<LoggedIn>());
    expect(find.byType(SignUpScreen), findsNothing);
    expect(find.text(english.text('home.title')), findsOneWidget);
    final body = lastBody(server, '/api/v1/auth/register');
    expect(body['email'], 'alice@example.com');
    expect(body['username'], 'alice');
    expect(body['password'], 'correct horse battery');
    expect(body['password_repeat'], 'correct horse battery');
    expect(body.containsKey('setup_code'), isFalse);
    expect(
      body.containsKey('locale'),
      isFalse,
      reason: 'the built-in English, which the server may not offer',
    );
  });

  testWidgets(
    'an account that waits for its code goes on to the code, then signs in',
    (tester) async {
      final server = accountServer(waitsForCode);
      await atSignUp(tester, server);

      await fillIn(tester);
      await submit(tester);
      expect(find.byType(VerifyEmailScreen), findsOneWidget);

      await tester.enterText(field('verify_email.code'), 'abcd2345');
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, english.text('verify_email.submit')),
      );
      await tester.pumpAndSettle();

      expect(lastBody(server, '/api/v1/auth/verify_email'), {
        'username_or_email': 'alice@example.com',
        'password': 'correct horse battery',
        'code': 'abcd2345',
        'device_name': 'macOS',
        'platform': 'macos',
      });
      expect(find.byType(VerifyEmailScreen), findsNothing);
      expect(find.byType(SignUpScreen), findsNothing);
      expect(find.text(english.text('home.title')), findsOneWidget);
    },
  );

  testWidgets('asks for the setup code once the server wants it', (
    tester,
  ) async {
    final server = accountServer(
      (request) => jsonDecode(request.body)['setup_code'] == 'ABCD2345'
          ? signedUp(request)
          : jsonAnswer({'error': 'invalid_setup_code'}, 403),
    );
    await atSignUp(tester, server);
    await fillIn(tester);

    await submit(tester);

    expect(
      find.text(english.text('sign_up.setup_code_explanation')),
      findsOneWidget,
    );
    expect(
      find.text(english.text('errors.invalid_setup_code')),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(submitButton()).onPressed,
      isNull,
      reason: 'until the code is typed',
    );

    await tester.enterText(field('sign_up.setup_code'), ' ABCD2345 ');
    await tester.pump();
    await submit(tester);

    expect(lastBody(server, '/api/v1/auth/register')['setup_code'], 'ABCD2345');
    expect(find.text(english.text('home.title')), findsOneWidget);
  });

  testWidgets('says why the server refused', (tester) async {
    await atSignUp(
      tester,
      accountServer((_) => jsonAnswer({'error': 'username_taken'}, 409)),
    );
    await fillIn(tester);

    await submit(tester);

    expect(find.text(english.text('errors.username_taken')), findsOneWidget);
    expect(find.byType(SignUpScreen), findsOneWidget);
  });

  testWidgets("sends the language of the server's catalog on screen", (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final server = accountServer(signedUp);
    await atSignUp(tester, server, followCatalog: true);

    await fillIn(tester);
    await submit(tester);

    expect(lastBody(server, '/api/v1/auth/register')['locale'], 'de');
  });
}
