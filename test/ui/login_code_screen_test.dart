import 'dart:convert';

import 'package:bookserver/data/session.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/login_code_screen.dart';
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

  /// A server whose login asks for a second factor, and whose code routes answer with
  /// [codeAnswer] — the session's tokens unless a test says otherwise.
  FakeServer twoFactorServer([
    http.Response Function(http.Request request)? codeAnswer,
  ]) => bookServer(
    (request) async => switch (request.url.path) {
      '/api/v1/auth/login' => jsonAnswer({
        'status': 'totp_required',
        'challenge_token': 'challenge-1',
        'challenge_expires_at': 1700000000,
      }),
      '/api/v1/auth/login/totp' || '/api/v1/auth/login/recovery_code' =>
        codeAnswer?.call(request) ??
            jsonAnswer({'status': 'ok', ...tokensJson()}),
      '/api/v1/libraries' => jsonAnswer([]),
      _ => notFound(),
    },
  );

  Finder codeField() => find.byType(TextField);
  Finder signInButton() =>
      find.widgetWithText(FilledButton, english.text('login.sign_in'));

  /// Signs in with a password on [server] and arrives at the code step.
  Future<SessionController> atTheCodeStep(
    WidgetTester tester,
    FakeServer server,
  ) async {
    final session = await pumpApp(
      tester,
      catalog: english,
      store: MemorySessionStore()
        ..connection = StoredConnection(server: testOrigin),
      server: server,
    );
    await tester.enterText(
      find.widgetWithText(TextField, english.text('login.username_or_email')),
      'alice',
    );
    await tester.enterText(
      find.widgetWithText(TextField, english.text('login.password')),
      'correct horse battery',
    );
    await tester.pump();
    await tester.tap(signInButton());
    await tester.pumpAndSettle();
    expect(find.byType(LoginCodeScreen), findsOneWidget);
    return session;
  }

  Future<void> signInWith(WidgetTester tester, String code) async {
    await tester.enterText(codeField(), code);
    await tester.pump();
    await tester.tap(signInButton());
    await tester.pumpAndSettle();
  }

  http.Request codeRequest(FakeServer server) => server.requests.lastWhere(
    (request) => request.url.path.startsWith('/api/v1/auth/login/'),
  );

  testWidgets('asks for the authenticator code first', (tester) async {
    await atTheCodeStep(tester, twoFactorServer());

    expect(find.text(english.text('login_code.title')), findsOneWidget);
    expect(
      find.text(english.text('login_code.app_explanation')),
      findsOneWidget,
    );
    expect(find.text(english.text('login_code.app_code')), findsOneWidget);
  });

  testWidgets('an authenticator code signs in and leaves the libraries', (
    tester,
  ) async {
    final server = twoFactorServer();
    final session = await atTheCodeStep(tester, server);

    await signInWith(tester, '123456');

    final request = codeRequest(server);
    expect(request.url.path, '/api/v1/auth/login/totp');
    expect(request.headers['authorization'], 'Bearer challenge-1');
    expect(jsonDecode(request.body), {'code': '123456'});
    expect(session.stage, isA<LoggedIn>());
    expect(find.byType(LoginCodeScreen), findsNothing);
    expect(find.text(english.text('home.title')), findsOneWidget);
  });

  testWidgets('the code field takes six digits and nothing else', (
    tester,
  ) async {
    await atTheCodeStep(tester, twoFactorServer());

    await tester.enterText(codeField(), '12a3-45 67890');

    expect(tester.widget<TextField>(codeField()).controller?.text, '123456');
  });

  testWidgets('a recovery code signs in on its own route', (tester) async {
    final server = twoFactorServer();
    await atTheCodeStep(tester, server);

    await tester.tap(find.text(english.text('login_code.use_recovery_code')));
    await tester.pumpAndSettle();
    expect(
      find.text(english.text('login_code.recovery_explanation')),
      findsOneWidget,
    );
    expect(find.text(english.text('login_code.recovery_code')), findsOneWidget);
    await signInWith(tester, ' abcd-efgh-jkmn-pqrs ');

    final request = codeRequest(server);
    expect(request.url.path, '/api/v1/auth/login/recovery_code');
    expect(jsonDecode(request.body), {'code': 'abcd-efgh-jkmn-pqrs'});
    expect(find.text(english.text('home.title')), findsOneWidget);
  });

  testWidgets('switching back to the app code empties the field', (
    tester,
  ) async {
    await atTheCodeStep(tester, twoFactorServer());
    await tester.tap(find.text(english.text('login_code.use_recovery_code')));
    await tester.pumpAndSettle();
    await tester.enterText(codeField(), 'ABCD');

    await tester.tap(find.text(english.text('login_code.use_app_code')));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(codeField()).controller?.text, isEmpty);
    expect(find.text(english.text('login_code.app_code')), findsOneWidget);
  });

  testWidgets('a wrong code says so and stays on the step', (tester) async {
    await atTheCodeStep(
      tester,
      twoFactorServer(
        (_) => jsonAnswer({'error': 'invalid_or_expired_code'}, 400),
      ),
    );

    await signInWith(tester, '000000');

    expect(
      find.text(english.text('errors.invalid_or_expired_code')),
      findsOneWidget,
    );
    expect(find.byType(LoginCodeScreen), findsOneWidget);
  });

  testWidgets('a step that ran out says to sign in again', (tester) async {
    await atTheCodeStep(
      tester,
      twoFactorServer((_) => jsonAnswer({'error': 'unauthorized'}, 401)),
    );

    await signInWith(tester, '123456');

    expect(find.text(english.text('errors.unauthorized')), findsOneWidget);
  });

  testWidgets('Back leads to the login screen', (tester) async {
    await atTheCodeStep(tester, twoFactorServer());

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(LoginCodeScreen), findsNothing);
    expect(signInButton(), findsOneWidget);
  });

  testWidgets('the same stage again keeps the step open', (tester) async {
    final session = await atTheCodeStep(tester, twoFactorServer());

    await session.load();
    await tester.pumpAndSettle();

    expect(find.byType(LoginCodeScreen), findsOneWidget);
  });
}
