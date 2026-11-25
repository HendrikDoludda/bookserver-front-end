import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/books_screen.dart';
import 'package:bookserver/ui/series_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_server.dart';
import '../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });
  // Every test asks the same server for the same covers: none may come from a test before.
  setUp(() => PaintingBinding.instance.imageCache.clear());

  /// Two libraries: "Manga" (1) with the series "alpha" (4), which has no books, and "Comics" (2)
  /// with the series "beta" (5); nothing has a cover.
  FakeServer twoLibraries() => bookServer(
    (request) async => switch (request.url.path) {
      '/api/v1/libraries' => jsonAnswer([
        {'id': 1, 'name': 'Manga', 'series_count': 1},
        {'id': 2, 'name': 'Comics', 'series_count': 1},
      ]),
      '/api/v1/libraries/1/series' => jsonAnswer([
        {'id': 4, 'name': 'alpha', 'book_count': 0},
      ]),
      '/api/v1/libraries/2/series' => jsonAnswer([
        {'id': 5, 'name': 'beta', 'book_count': 0},
      ]),
      '/api/v1/series/4/books' => jsonAnswer([]),
      _ => notFound(),
    },
  );

  /// Makes the window [width] wide; the test window is 800 wide otherwise.
  void windowWidth(WidgetTester tester, double width) {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Starts signed in and opens the library "Manga".
  Future<void> openManga(WidgetTester tester, FakeServer server) async {
    await pumpApp(
      tester,
      catalog: english,
      store: signedInStore(),
      server: server,
    );
    await tester.pumpAndSettle();
    await tester.tap(cardNamed('Manga'));
    await tester.pumpAndSettle();
  }

  Finder entry(String name) => find.widgetWithText(ListTile, name);
  Finder sidebarButton() => find.byTooltip(english.text('menu.libraries'));

  testWidgets(
    'in a wide window the libraries sit beside the series until their button hides them',
    (tester) async {
      windowWidth(tester, 1000);
      await openManga(tester, twoLibraries());

      expect(entry('Manga'), findsOneWidget);
      expect(entry('Comics'), findsOneWidget);
      expect(find.byType(Drawer), findsNothing, reason: 'beside, not over');
      expect(
        find.byType(CloseButton),
        findsNothing,
        reason: 'the top bar\'s button stays in view',
      );
      expect(
        tester.getTopRight(entry('Comics')).dx,
        lessThan(tester.getTopLeft(cardNamed('alpha')).dx),
      );

      await tester.tap(sidebarButton());
      await tester.pumpAndSettle();
      expect(entry('Comics'), findsNothing);
      expect(cardNamed('alpha'), findsOneWidget);

      await tester.tap(sidebarButton());
      await tester.pumpAndSettle();
      expect(entry('Comics'), findsOneWidget);
    },
  );

  testWidgets(
    'in a narrow window the button opens the libraries over the series',
    (tester) async {
      await openManga(tester, twoLibraries());
      expect(entry('Comics'), findsNothing);

      await tester.tap(sidebarButton());
      await tester.pumpAndSettle();

      expect(find.byType(Drawer), findsOneWidget);
      expect(entry('Comics'), findsOneWidget);
    },
  );

  testWidgets(
    'over the series, the close button at the top of the list closes it',
    (tester) async {
      final server = twoLibraries();
      await openManga(tester, server);
      await tester.tap(sidebarButton());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();

      expect(find.byType(Drawer), findsNothing);
      expect(find.byType(SeriesScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Manga'), findsOneWidget);
      expect(requestedPaths(server), [
        '/api/v1/libraries',
        '/api/v1/libraries/1/series',
      ]);
    },
  );

  testWidgets('a drag from the left edge never opens the libraries', (
    tester,
  ) async {
    await openManga(tester, twoLibraries());

    await tester.dragFrom(const Offset(1, 300), const Offset(300, 0));
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsNothing);
  });

  testWidgets('Back stays beside the button', (tester) async {
    await openManga(tester, twoLibraries());

    expect(find.byType(BackButton), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SeriesScreen), findsNothing);
  });

  testWidgets('marks the library being browsed', (tester) async {
    windowWidth(tester, 1000);
    await openManga(tester, twoLibraries());

    expect(tester.widget<ListTile>(entry('Manga')).selected, isTrue);
    expect(tester.widget<ListTile>(entry('Comics')).selected, isFalse);
  });

  testWidgets(
    'choosing another library shows its series, and Back leads to the libraries',
    (tester) async {
      final server = twoLibraries();
      await openManga(tester, server);

      await tester.tap(sidebarButton());
      await tester.pumpAndSettle();
      await tester.tap(entry('Comics'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Comics'), findsOneWidget);
      expect(cardNamed('beta'), findsOneWidget);
      expect(
        requestedPaths(server),
        [
          '/api/v1/libraries',
          '/api/v1/libraries/1/series',
          '/api/v1/libraries/2/series',
        ],
        reason: 'the libraries come from the grid, not a request of their own',
      );

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(SeriesScreen), findsNothing);
      expect(find.text(english.text('home.title')), findsOneWidget);
    },
  );

  testWidgets(
    'back from a library chosen in the sidebar, the libraries load again once',
    (tester) async {
      final server = twoLibraries();
      await openManga(tester, server);
      await tester.tap(sidebarButton());
      await tester.pumpAndSettle();
      await tester.tap(entry('Comics'));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(requestedPaths(server), [
        '/api/v1/libraries',
        '/api/v1/libraries/1/series',
        '/api/v1/libraries/2/series',
        '/api/v1/libraries',
      ]);
    },
  );

  testWidgets('choosing the library being browsed only closes the list', (
    tester,
  ) async {
    final server = twoLibraries();
    await openManga(tester, server);

    await tester.tap(sidebarButton());
    await tester.pumpAndSettle();
    await tester.tap(entry('Manga'));
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsNothing);
    expect(find.widgetWithText(AppBar, 'Manga'), findsOneWidget);
    expect(requestedPaths(server), [
      '/api/v1/libraries',
      '/api/v1/libraries/1/series',
    ]);
  });

  testWidgets(
    "a series' books have the libraries beside them too, their library marked",
    (tester) async {
      windowWidth(tester, 1000);
      await openManga(tester, twoLibraries());
      await tester.tap(cardNamed('alpha'));
      await tester.pumpAndSettle();
      expect(find.byType(BooksScreen), findsOneWidget);

      expect(tester.widget<ListTile>(entry('Manga')).selected, isTrue);

      await tester.tap(entry('Comics'));
      await tester.pumpAndSettle();
      expect(find.byType(BooksScreen), findsNothing);
      expect(find.widgetWithText(AppBar, 'Comics'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(english.text('home.title')), findsOneWidget);
    },
  );
}
