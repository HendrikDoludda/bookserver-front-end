import 'package:bookserver/data/auth_api.dart';
import 'package:bookserver/data/session.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_session_store.dart';
import 'support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });

  Future<void> start(WidgetTester tester, [StoredConnection? stored]) =>
      pumpApp(
        tester,
        catalog: english,
        store: MemorySessionStore()..connection = stored,
        server: bookServer(),
      );

  testWidgets('takes its title from the catalog', (tester) async {
    await start(tester);

    expect(
      tester.widget<Title>(find.byType(Title)).title,
      english.text('app.name'),
    );
  });

  testWidgets('follows the platform into dark mode', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await start(tester);

    final screen = tester.element(find.text(english.text('server.title')));
    expect(Theme.of(screen).brightness, Brightness.dark);
  });

  group('opens on the screen the stored record calls for', () {
    testWidgets('nothing stored: the address screen', (tester) async {
      await start(tester);
      expect(find.text(english.text('server.title')), findsOneWidget);
    });

    testWidgets('a server: the login screen', (tester) async {
      await start(tester, StoredConnection(server: testOrigin));
      expect(
        find.text(english.text('login.username_or_email')),
        findsOneWidget,
      );
    });

    testWidgets('a server and a session: the home screen', (tester) async {
      await start(
        tester,
        StoredConnection(server: testOrigin)
            .withTokens(SessionTokens.fromJson(tokensJson())),
      );
      expect(find.text(english.text('home.title')), findsOneWidget);
    });
  });
}
