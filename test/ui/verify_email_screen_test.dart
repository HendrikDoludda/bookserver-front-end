import 'dart:convert';

import 'package:bookserver/data/session.dart';
import 'package:bookserver/i18n/catalog.dart';
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

  /// A server whose login refuses until the address is confirmed; the verification answers with
  /// [verify], the resend with [resend].
  FakeServer unverifiedServer({
    http.Response Function()? verify,
    http.Response Function()? resend,
  }) => bookServer(
    (request) async => switch (request.url.path) {
      '/api/v1/auth/login' => jsonAnswer({'error': 'email_not_verified'}, 403),
      '/api/v1/auth/verify_email' =>
        verify?.call() ?? jsonAnswer({'status': 'ok', ...tokensJson()}),
      '/api/v1/auth/verify_email/resend' =>
        resend?.call() ?? http.Response('', 202),
      '/api/v1/libraries' => jsonAnswer([]),
      _ => notFound(),
    },
  );

  Finder codeField() =>
      find.widgetWithText(TextField, english.text('verify_email.code'));
  Finder confirmButton() =>
      find.widgetWithText(FilledButton, english.text('verify_email.submit'));

  /// Signs in with an account whose address isn't confirmed, which leads to the code screen.
  Future<void> atTheCodeScreen(WidgetTester tester, FakeServer server) async {
    await pumpApp(
      tester,
      catalog: english,
      store: MemorySessionStore()
        ..connection = StoredConnection(server: testOrigin),
      server: server,
    );
    await tester.enterText(
      find.widgetWithText(TextField, english.text('login.username_or_email')),
      ' alice ',
    );
    await tester.enterText(
      find.widgetWithText(TextField, english.text('login.password')),
      'correct horse battery',
    );
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, english.text('login.sign_in')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(VerifyEmailScreen), findsOneWidget);
  }

  Future<void> confirm(WidgetTester tester, String code) async {
    await tester.enterText(codeField(), code);
    await tester.pump();
    await tester.tap(confirmButton());
    await tester.pumpAndSettle();
  }

  Map<String, Object?> lastBody(FakeServer server, String path) =>
      jsonDecode(server.requests.lastWhere((r) => r.url.path == path).body)
          as Map<String, Object?>;

  testWidgets(
    "a login waiting for its code confirms with the login's name and password",
    (tester) async {
      final server = unverifiedServer();
      await atTheCodeScreen(tester, server);
      expect(
        find.text(english.text('verify_email.explanation')),
        findsOneWidget,
      );

      await confirm(tester, ' ABCD2345 ');

      final body = lastBody(server, '/api/v1/auth/verify_email');
      expect(body['username_or_email'], 'alice');
      expect(body['password'], 'correct horse battery');
      expect(body['code'], 'ABCD2345');
      expect(find.byType(VerifyEmailScreen), findsNothing);
      expect(find.text(english.text('home.title')), findsOneWidget);
    },
  );

  testWidgets('the button waits for a code', (tester) async {
    await atTheCodeScreen(tester, unverifiedServer());

    expect(tester.widget<FilledButton>(confirmButton()).onPressed, isNull);
  });

  testWidgets('a wrong code says so and stays', (tester) async {
    await atTheCodeScreen(
      tester,
      unverifiedServer(
        verify: () => jsonAnswer({'error': 'invalid_or_expired_code'}, 400),
      ),
    );

    await confirm(tester, 'WRONG234');

    expect(
      find.text(english.text('errors.invalid_or_expired_code')),
      findsOneWidget,
    );
    expect(find.byType(VerifyEmailScreen), findsOneWidget);
  });

  testWidgets('a new code is asked for with the same name', (tester) async {
    final server = unverifiedServer();
    await atTheCodeScreen(tester, server);

    await tester.tap(find.text(english.text('verify_email.resend')));
    await tester.pumpAndSettle();

    expect(lastBody(server, '/api/v1/auth/verify_email/resend'), {
      'username_or_email': 'alice',
    });
    expect(find.text(english.text('verify_email.resent')), findsOneWidget);
  });

  testWidgets('a server without email says so', (tester) async {
    await atTheCodeScreen(
      tester,
      unverifiedServer(
        resend: () => jsonAnswer({'error': 'email_not_configured'}, 503),
      ),
    );

    await tester.tap(find.text(english.text('verify_email.resend')));
    await tester.pumpAndSettle();

    expect(
      find.text(english.text('errors.email_not_configured')),
      findsOneWidget,
    );
    expect(find.text(english.text('verify_email.resent')), findsNothing);
  });
}
