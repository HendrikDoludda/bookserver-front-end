import 'dart:async';
import 'dart:io';

import 'package:bookserver/data/session.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/login_screen.dart';
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

  late MemorySessionStore store;
  setUp(() {
    store = MemorySessionStore()
      ..connection = StoredConnection(server: testOrigin);
  });

  Finder nameField() =>
      find.widgetWithText(TextField, english.text('login.username_or_email'));
  Finder passwordField() =>
      find.widgetWithText(TextField, english.text('login.password'));
  Finder signInButton() =>
      find.widgetWithText(FilledButton, english.text('login.sign_in'));
  Finder homeScreen() => find.text(english.text('home.title'));

  /// The login screen of a server that answers the login with [login].
  Future<void> atLogin(
    WidgetTester tester,
    Future<http.Response> Function() login,
  ) => pumpApp(
    tester,
    catalog: english,
    store: store,
    server: bookServer((request) => login()),
  );

  Future<void> fillIn(WidgetTester tester) async {
    await tester.enterText(nameField(), ' alice ');
    await tester.enterText(passwordField(), 'correct horse battery');
    // The sign-in button enables itself on the next frame, as it would for a person typing.
    await tester.pump();
  }

  testWidgets('signs in and shows the home screen', (tester) async {
    await atLogin(
      tester,
      () async => jsonAnswer({'status': 'ok', ...tokensJson()}),
    );

    await fillIn(tester);
    await tester.tap(signInButton());
    await tester.pumpAndSettle();

    expect(homeScreen(), findsOneWidget);
    expect(store.connection?.tokens?.sessionToken, 'session-1');
  });

  testWidgets('sends the name without the spaces around it', (tester) async {
    final server = bookServer(
      (_) async => jsonAnswer({'status': 'ok', ...tokensJson()}),
    );
    await pumpApp(tester, catalog: english, store: store, server: server);

    await fillIn(tester);
    await tester.tap(signInButton());
    await tester.pumpAndSettle();

    expect(server.requests.last.body, contains('"username_or_email":"alice"'));
  });

  testWidgets('Enter in the password field signs in', (tester) async {
    await atLogin(
      tester,
      () async => jsonAnswer({'status': 'ok', ...tokensJson()}),
    );

    await fillIn(tester);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(homeScreen(), findsOneWidget);
  });

  testWidgets('the sign-in button waits for a name and a password', (
    tester,
  ) async {
    await atLogin(
      tester,
      () async => jsonAnswer({'status': 'ok', ...tokensJson()}),
    );
    VoidCallback? onPressed() =>
        tester.widget<FilledButton>(signInButton()).onPressed;

    expect(onPressed(), isNull);
    await tester.enterText(nameField(), 'alice');
    await tester.pump();
    expect(onPressed(), isNull);
    await tester.enterText(passwordField(), 'correct horse battery');
    await tester.pump();
    expect(onPressed(), isNotNull);
  });

  testWidgets('hides the password and offers autofill', (tester) async {
    await atLogin(
      tester,
      () async => jsonAnswer({'status': 'ok', ...tokensJson()}),
    );

    final name = tester.widget<TextField>(nameField());
    final password = tester.widget<TextField>(passwordField());
    expect(password.obscureText, isTrue);
    expect(password.autofillHints, contains(AutofillHints.password));
    expect(name.autofillHints, contains(AutofillHints.username));
    expect(
      find.ancestor(of: passwordField(), matching: find.byType(AutofillGroup)),
      findsOneWidget,
    );
  });

  testWidgets('shows the server it signs in to', (tester) async {
    await atLogin(
      tester,
      () async => jsonAnswer({'status': 'ok', ...tokensJson()}),
    );

    expect(find.text('books.example.ts.net'), findsOneWidget);
  });

  testWidgets('says why the server refused', (tester) async {
    final cases = {
      (401, 'incorrect_credentials'): 'errors.incorrect_credentials',
      (429, 'too_many_attempts'): 'errors.too_many_attempts',
      (403, 'email_not_verified'): 'errors.email_not_verified',
      (400, 'a_key_this_app_does_not_know'): 'connection.unexpected_answer',
    };
    for (final MapEntry(key: (status, serverKey), value: textKey)
        in cases.entries) {
      await tester.pumpWidget(const SizedBox());
      store.connection = StoredConnection(server: testOrigin);
      await atLogin(
        tester,
        () async => jsonAnswer({'error': serverKey}, status),
      );

      await fillIn(tester);
      await tester.tap(signInButton());
      await tester.pumpAndSettle();

      expect(
        find.text(english.text(textKey)),
        findsOneWidget,
        reason: serverKey,
      );
      expect(store.connection?.tokens, isNull, reason: serverKey);
    }
  });

  testWidgets('says that nothing answers', (tester) async {
    await atLogin(
      tester,
      () async => throw const SocketException('Connection refused'),
    );

    await fillIn(tester);
    await tester.tap(signInButton());
    await tester.pumpAndSettle();

    expect(find.text(english.text('connection.unreachable')), findsOneWidget);
  });

  testWidgets(
    'tells an account with two-factor that the app cannot do it yet',
    (tester) async {
      await atLogin(
        tester,
        () async => jsonAnswer({
          'status': 'totp_required',
          'challenge_token': 'challenge-1',
          'challenge_expires_at': 1700000000,
        }),
      );

      await fillIn(tester);
      await tester.tap(signInButton());
      await tester.pumpAndSettle();

      expect(find.text(english.text('login.totp_unavailable')), findsOneWidget);
      expect(nameField(), findsOneWidget);
    },
  );

  testWidgets('shows why the last session ended until the next try', (
    tester,
  ) async {
    final session = SessionController(
      store: store,
      client: bookServer(
        (_) async => jsonAnswer({'error': 'incorrect_credentials'}, 401),
      ).client,
      platform: 'macos',
    );
    await session.load();
    await pumpScreen(
      tester,
      catalog: english,
      screen: LoginScreen(
        session: session,
        server: testOrigin,
        endedKey: 'errors.unauthorized',
      ),
    );

    expect(find.text(english.text('errors.unauthorized')), findsOneWidget);

    await fillIn(tester);
    await tester.tap(signInButton());
    await tester.pumpAndSettle();

    expect(find.text(english.text('errors.unauthorized')), findsNothing);
    expect(
      find.text(english.text('errors.incorrect_credentials')),
      findsOneWidget,
    );
  });

  testWidgets('shows that it is busy while signing in', (tester) async {
    final login = Completer<http.Response>();
    await atLogin(tester, () => login.future);

    await fillIn(tester);
    await tester.tap(signInButton());
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(signInButton()).onPressed, isNull);
    expect(tester.widget<TextField>(passwordField()).enabled, isFalse);

    login.complete(jsonAnswer({'status': 'ok', ...tokensJson()}));
    await tester.pumpAndSettle();

    expect(homeScreen(), findsOneWidget);
  });

  testWidgets('"Change server" goes back to the address screen', (
    tester,
  ) async {
    await atLogin(
      tester,
      () async => jsonAnswer({'status': 'ok', ...tokensJson()}),
    );

    await tester.tap(find.text(english.text('login.change_server')));
    await tester.pumpAndSettle();

    expect(find.text(english.text('server.title')), findsOneWidget);
    expect(store.connection, isNull);
  });
}
