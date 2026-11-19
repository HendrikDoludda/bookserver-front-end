import 'package:bookserver/data/session.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
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

  Finder field(String key) => find.widgetWithText(TextField, english.text(key));
  Finder submitButton() =>
      find.widgetWithText(FilledButton, english.text('password_reset.submit'));

  /// The reset screen alone, on a server whose reset answers with [answer].
  Future<void> atReset(WidgetTester tester, http.Response answer) async {
    final session = SessionController(
      store: MemorySessionStore()
        ..connection = StoredConnection(server: testOrigin),
      client: bookServer((_) async => answer).client,
      platform: 'macos',
    );
    await session.load();
    await pumpScreen(
      tester,
      catalog: english,
      screen: ResetPasswordScreen(session: session, email: 'alice@example.com'),
    );
  }

  Future<void> fillIn(WidgetTester tester) async {
    await tester.enterText(field('password_reset.code'), 'ABCD2345');
    for (final key in [
      'password_reset.new_password',
      'password_reset.new_password_repeat',
    ]) {
      await tester.enterText(field(key), 'a new pw 1234');
    }
    await tester.pump();
  }

  testWidgets('shows the password rule, and waits for all three fields', (
    tester,
  ) async {
    await atReset(tester, http.Response('', 200));

    expect(
      find.text(english.text('password_reset.password_rule')),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(submitButton()).onPressed, isNull);
    await fillIn(tester);
    expect(tester.widget<FilledButton>(submitButton()).onPressed, isNotNull);
  });

  testWidgets('says why the server refused, and stays', (tester) async {
    final cases = {
      (400, 'invalid_or_expired_code'): 'errors.invalid_or_expired_code',
      (400, 'passwords_do_not_match'): 'errors.passwords_do_not_match',
      (400, 'password_too_short'): 'errors.password_too_short',
      (429, 'too_many_attempts'): 'errors.too_many_attempts',
    };
    for (final MapEntry(key: (status, key), value: textKey) in cases.entries) {
      await tester.pumpWidget(const SizedBox());
      await atReset(tester, jsonAnswer({'error': key}, status));

      await fillIn(tester);
      await tester.tap(submitButton());
      await tester.pumpAndSettle();

      expect(find.text(english.text(textKey)), findsOneWidget, reason: key);
      expect(find.byType(ResetPasswordScreen), findsOneWidget, reason: key);
    }
  });
}
