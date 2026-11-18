import 'dart:async';

import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/books_screen.dart';
import 'package:bookserver/ui/series_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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

  /// Series exactly as `GET /api/v1/libraries/{id}/series` sends them, each with one book unless
  /// [bookCounts] names its number.
  http.Response series(
    Map<int, String> names, {
    Map<int, int> bookCounts = const {},
  }) => jsonAnswer([
    for (final MapEntry(key: id, value: name) in names.entries)
      {
        'id': id,
        'name': name,
        'description': null,
        'cover_image': null,
        'start_release_year': null,
        'end_release_year': null,
        'book_count': bookCounts[id] ?? 1,
      },
  ]);

  /// A server with one library, "Manga" (id 3), whose series list is [answer]'s; nothing has a
  /// cover.
  FakeServer mangaServer(Future<http.Response> Function() answer) => bookServer(
    (request) => switch (request.url.path) {
      '/api/v1/libraries' => Future.value(
        jsonAnswer([
          {'id': 3, 'name': 'Manga', 'series_count': 1},
        ]),
      ),
      '/api/v1/libraries/3/series' => answer(),
      _ => Future.value(notFound()),
    },
  );

  /// Starts the app signed in and taps the library "Manga".
  Future<void> openManga(WidgetTester tester, FakeServer server) async {
    await pumpApp(
      tester,
      catalog: english,
      store: signedInStore(),
      server: server,
    );
    await tester.pumpAndSettle();
    await tester.tap(cardNamed('Manga'));
  }

  VoidCallback? reloadAction(WidgetTester tester) => tester
      .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh))
      .onPressed;

  testWidgets("lists the library's series under the library's name", (
    tester,
  ) async {
    final server = mangaServer(() async => series({4: 'alpha', 5: 'beta'}));
    await openManga(tester, server);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Manga'), findsOneWidget);
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);
    expect(requestedPaths(server), [
      '/api/v1/libraries',
      '/api/v1/libraries/3/series',
    ]);
    final request = server.requests.singleWhere(
      (request) => request.url.path == '/api/v1/libraries/3/series',
    );
    expect(request.method, 'GET');
    expect(request.headers['authorization'], 'Bearer session-1');
  });

  testWidgets("shows each series' cover", (tester) async {
    final server = mangaServer(() async => series({4: 'alpha', 5: 'beta'}));
    await openManga(tester, server);
    await tester.pumpAndSettle();

    expect(
      requestedCovers(server),
      containsAll(['/api/v1/covers/series/4', '/api/v1/covers/series/5']),
    );
  });

  testWidgets('shows how many books each series holds under its name', (
    tester,
  ) async {
    final server = mangaServer(
      () async => series(
        {4: 'alpha', 5: 'beta', 6: 'gamma'},
        bookCounts: {4: 1, 5: 0, 6: 3},
      ),
    );
    await openManga(tester, server);
    await tester.pumpAndSettle();

    for (final (name, count) in [('alpha', 1), ('beta', 0), ('gamma', 3)]) {
      expect(
        find.descendant(
          of: cardNamed(name),
          matching: find.text(english.plural('browse.book_count', count)),
        ),
        findsOneWidget,
        reason: name,
      );
    }
  });

  testWidgets('says so when the library has no series', (tester) async {
    await openManga(tester, mangaServer(() async => series({})));
    await tester.pumpAndSettle();

    expect(find.text(english.text('browse.series_empty')), findsOneWidget);
  });

  testWidgets('shows progress while the series load', (tester) async {
    final answer = Completer<http.Response>();
    await openManga(tester, mangaServer(() => answer.future));
    await finishTransition(tester);

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(reloadAction(tester), isNull, reason: 'one load at a time');

    answer.complete(series({4: 'alpha'}));
    await tester.pumpAndSettle();

    expect(find.text('alpha'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(reloadAction(tester), isNotNull);
  });

  testWidgets("says why the series didn't load, with Reload under it", (
    tester,
  ) async {
    var calls = 0;
    final server = mangaServer(
      () async => ++calls == 1 ? http.Response('', 503) : series({4: 'alpha'}),
    );
    await openManga(tester, server);
    await tester.pumpAndSettle();

    expect(find.text(english.text('connection.unreachable')), findsOneWidget);

    await tester.tap(
      find.widgetWithText(FilledButton, english.text('browse.reload')),
    );
    await tester.pumpAndSettle();

    expect(find.text('alpha'), findsOneWidget);
    expect(find.text(english.text('connection.unreachable')), findsNothing);
  });

  testWidgets('Reload at the top loads the series again', (tester) async {
    var calls = 0;
    final server = mangaServer(
      () async =>
          ++calls == 1 ? series({4: 'alpha'}) : series({4: 'alpha', 5: 'beta'}),
    );
    await openManga(tester, server);
    await tester.pumpAndSettle();
    expect(find.text('beta'), findsNothing);

    await tester.tap(find.byTooltip(english.text('browse.reload')));
    await tester.pumpAndSettle();

    expect(find.text('beta'), findsOneWidget);
    expect(requestedPaths(server), [
      '/api/v1/libraries',
      '/api/v1/libraries/3/series',
      '/api/v1/libraries/3/series',
    ]);
  });

  testWidgets('Back leads to the libraries', (tester) async {
    await openManga(tester, mangaServer(() async => series({4: 'alpha'})));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(SeriesScreen), findsNothing);
    expect(find.text(english.text('home.title')), findsOneWidget);
  });

  testWidgets("a tap on a series opens its books under the series' name", (
    tester,
  ) async {
    final server = bookServer(
      (request) async => switch (request.url.path) {
        '/api/v1/libraries' => jsonAnswer([
          {'id': 3, 'name': 'Manga', 'series_count': 1},
        ]),
        '/api/v1/libraries/3/series' => series({4: 'alpha', 5: 'beta'}),
        '/api/v1/series/5/books' => jsonAnswer([]),
        _ => notFound(),
      },
    );
    await openManga(tester, server);
    await tester.pumpAndSettle();

    await tester.tap(cardNamed('beta'));
    await tester.pumpAndSettle();

    expect(find.byType(BooksScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'beta'), findsOneWidget);
    expect(requestedPaths(server).last, '/api/v1/series/5/books');
  });
}
