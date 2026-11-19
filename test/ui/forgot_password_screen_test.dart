import 'dart:convert';

import 'package:bookserver/data/session.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/forgot_password_screen.dart';
import 'package:bookserver/ui/reset_password_screen.dart';
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

  /// A server whose reset request answers with [request], and whose reset takes any code.
  FakeServer resetServer([http.Response Function()? request]) => bookServer(
    (http.Request r) async => switch (r.url.path) {
      '/api/v1/auth/password_reset' =>
        request?.call() ?? http.Response('', 202),
      '/api/v1/auth/password_reset/confirm' => http.Response('', 200),
      _ => notFound(),
    },
  );

  Finder field(String key) => find.widgetWithText(TextField, english.text(key));
  Finder button(String key) =>
      find.widgetWithText(FilledButton, english.text(key));

  Map<String, Object?> lastBody(FakeServer server, String path) =>
      jsonDecode(server.requests.lastWhere((r) => r.url.path == path).body)
          as Map<String, Object?>;

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Starts on the login screen of [server] and opens the reset from there.
  Future<void> atForgotPassword(WidgetTester tester, FakeServer server) async {
    await pumpApp(
      tester,
      catalog: english,
      store: MemorySessionStore()
        ..connection = StoredConnection(server: testOrigin),
      server: server,
    );
    await tapAndSettle(
      tester,
      find.text(english.text('login.forgot_password')),
    );
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
  }

  Future<void> sendCodeTo(WidgetTester tester, String email) async {
    await tester.enterText(field('password_reset.email'), email);
    await tester.pump();
    await tapAndSettle(tester, button('password_reset.send'));
  }

  testWidgets('the button waits for an address', (tester) async {
    await atForgotPassword(tester, resetServer());

    expect(
      find.text(english.text('password_reset.explanation')),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(button('password_reset.send')).onPressed,
      isNull,
    );
  });

  testWidgets(
    'a code to the address, a new password, and back to the login with the address filled in',
    (tester) async {
      final server = resetServer();
      await atForgotPassword(tester, server);

      await sendCodeTo(tester, ' alice@example.com ');

      expect(lastBody(server, '/api/v1/auth/password_reset'), {
        'email': 'alice@example.com',
      });
      expect(find.byType(ResetPasswordScreen), findsOneWidget);
      expect(
        find.text(english.text('password_reset.new_explanation')),
        findsOneWidget,
      );

      await tester.enterText(field('password_reset.code'), ' abcd2345 ');
      await tester.enterText(
        field('password_reset.new_password'),
        'a new password 123',
      );
      await tester.enterText(
        field('password_reset.new_password_repeat'),
        'a new password 123',
      );
      await tester.pump();
      await tapAndSettle(tester, button('password_reset.submit'));

      expect(lastBody(server, '/api/v1/auth/password_reset/confirm'), {
        'email': 'alice@example.com',
        'code': 'abcd2345',
        'new_password': 'a new password 123',
        'new_password_repeat': 'a new password 123',
      });
      expect(find.byType(ResetPasswordScreen), findsNothing);
      expect(find.byType(ForgotPasswordScreen), findsNothing);
      expect(find.text(english.text('password_reset.done')), findsOneWidget);
      expect(find.text('alice@example.com'), findsOneWidget);
    },
  );

  testWidgets('Back from both screens leaves the login screen as it was', (
    tester,
  ) async {
    await atForgotPassword(tester, resetServer());
    await sendCodeTo(tester, 'alice@example.com');

    await tapAndSettle(tester, find.byType(BackButton));
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    await tapAndSettle(tester, find.byType(BackButton));

    expect(find.byType(ForgotPasswordScreen), findsNothing);
    expect(find.text(english.text('password_reset.done')), findsNothing);
  });

  testWidgets('a server without email says so', (tester) async {
    await atForgotPassword(
      tester,
      resetServer(() => jsonAnswer({'error': 'email_not_configured'}, 503)),
    );

    await sendCodeTo(tester, 'alice@example.com');

    expect(
      find.text(english.text('errors.email_not_configured')),
      findsOneWidget,
    );
    expect(find.byType(ResetPasswordScreen), findsNothing);
  });
}
