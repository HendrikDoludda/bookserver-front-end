import 'package:bookserver/data/auth_api.dart';
import 'package:bookserver/data/session.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/books_screen.dart';
import 'package:bookserver/ui/series_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_server.dart';
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

  testWidgets(
    'a session that ends on a pushed screen leaves only the login screen',
    (tester) async {
      final refused = jsonAnswer({'error': 'unauthorized'}, 401);
      var bookLists = 0;
      final server = bookServer(
        (request) async => switch (request.url.path) {
          '/api/v1/libraries' => jsonAnswer([
            {'id': 3, 'name': 'Manga', 'series_count': 1},
          ]),
          '/api/v1/libraries/3/series' => jsonAnswer([
            {'id': 4, 'name': 'alpha', 'book_count': 1},
          ]),
          '/api/v1/series/4/books' =>
            ++bookLists == 1 ? jsonAnswer([]) : refused,
          '/api/v1/auth/refresh' => refused,
          _ => notFound(),
        },
      );
      await pumpApp(
        tester,
        catalog: english,
        store: signedInStore(),
        server: server,
      );
      await tester.pumpAndSettle();
      await tester.tap(cardNamed('Manga'));
      await tester.pumpAndSettle();
      await tester.tap(cardNamed('alpha'));
      await tester.pumpAndSettle();
      expect(find.byType(BooksScreen), findsOneWidget);

      await tester.tap(find.byTooltip(english.text('browse.reload')));
      await tester.pumpAndSettle();

      expect(
        find.text(english.text('login.username_or_email')),
        findsOneWidget,
      );
      expect(find.text(english.text('errors.unauthorized')), findsOneWidget);
      expect(find.byType(SeriesScreen), findsNothing);
      expect(find.byType(BooksScreen), findsNothing);
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
        isFalse,
      );
    },
  );
}
