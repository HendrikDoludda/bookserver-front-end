import 'package:bookserver/app.dart';
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

  testWidgets(
    "switches to the server's catalog in the device's language once it arrives",
    (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final server = bookServer(
        (request) async => switch (request.url.pathSegments) {
          ['api', 'v1', 'locales'] => jsonAnswer([
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
          ['api', 'v1', 'locales', 'de', 'translations'] => jsonAnswer({
            'app': {'name': 'Bücherserver'},
            'login': {'title': 'Willkommen zurück', 'sign_in': 'Anmelden'},
          }),
          _ => notFound(),
        },
      );

      await pumpApp(
        tester,
        catalog: english,
        store: MemorySessionStore()
          ..connection = StoredConnection(server: testOrigin),
        server: server,
        followCatalog: true,
      );
      await tester.pumpAndSettle();

      expect(find.text('Willkommen zurück'), findsOneWidget);
      expect(find.text('Anmelden'), findsOneWidget);
      expect(find.text(english.text('login.sign_in')), findsNothing);
      expect(tester.widget<Title>(find.byType(Title)).title, 'Bücherserver');
      expect(
        MaterialLocalizations.of(tester.element(find.text('Willkommen zurück')))
            .backButtonTooltip,
        'Zurück',
        reason: "Material's texts switch with the catalog",
      );
      expect(
        find.text(english.text('login.username_or_email')),
        findsOneWidget,
        reason: "a text the server's catalog lacks stays the built-in English",
      );
    },
  );

  group("Material's own texts", () {
    /// Starts the app on the address screen with a catalog in [language], and answers a context on
    /// that screen.
    Future<BuildContext> startIn(WidgetTester tester, String language) async {
      await pumpApp(
        tester,
        catalog: Catalog.fromJson(
          <String, Object?>{},
          language: language,
          fallback: english,
        ),
        store: MemorySessionStore(),
        server: bookServer(),
      );
      return tester.element(find.text(english.text('server.title')));
    }

    test(
      "follow the catalog's language where material_ui has it, else English",
      () {
        expect(materialLocaleOf('de'), const Locale('de'));
        expect(materialLocaleOf('en'), const Locale('en'));
        expect(materialLocaleOf('pt-BR'), const Locale('pt', 'BR'));
        expect(materialLocaleOf('qaa'), const Locale('en'));
      },
    );

    testWidgets('are German with a German catalog', (tester) async {
      final screen = await startIn(tester, 'de');

      expect(Localizations.localeOf(screen), const Locale('de'));
      final texts = MaterialLocalizations.of(screen);
      expect(texts.backButtonTooltip, 'Zurück');
      expect(texts.pasteButtonLabel, 'Einsetzen');
    });

    testWidgets('stay English for a language material_ui lacks', (
      tester,
    ) async {
      final screen = await startIn(tester, 'qaa');

      expect(Localizations.localeOf(screen), const Locale('en'));
      expect(MaterialLocalizations.of(screen).backButtonTooltip, 'Back');
      expect(tester.takeException(), isNull);
    });

    testWidgets('turn the layout right-to-left for Arabic', (tester) async {
      final screen = await startIn(tester, 'ar');

      expect(Directionality.of(screen), TextDirection.rtl);
    });
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
