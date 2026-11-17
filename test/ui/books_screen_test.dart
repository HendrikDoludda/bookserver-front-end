import 'dart:async';

import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/books_screen.dart';
import 'package:bookserver/ui/readers/page_reader.dart';
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

  /// A book exactly as `GET /api/v1/series/{id}/books` sends one.
  Map<String, Object?> bookJson(
    int id, {
    String title = 'Alpha',
    int? volume,
    int? chapter,
    String format = 'cbz',
  }) => {
    'id': id,
    'title': title,
    'author': 'Unknown Author',
    'format': format,
    'tags': <String>[],
    'description': null,
    'language': null,
    'page_count': null,
    'series': 4,
    'volume_number': volume,
    'chapter_number': chapter,
    'page_number': null,
    'last_modified': 1767225600,
    'file_size': 1024,
  };

  /// A server with the library "Manga" (id 3), its one series "alpha" (id 4), and that series'
  /// books from [answer]; nothing has a cover.
  FakeServer alphaServer(Future<http.Response> Function() answer) => bookServer(
    (request) => switch (request.url.path) {
      '/api/v1/libraries' => Future.value(
        jsonAnswer([
          {'id': 3, 'name': 'Manga'},
        ]),
      ),
      '/api/v1/libraries/3/series' => Future.value(
        jsonAnswer([
          {'id': 4, 'name': 'alpha'},
        ]),
      ),
      '/api/v1/series/4/books' => answer(),
      _ => Future.value(notFound()),
    },
  );

  /// Starts the app signed in, opens the library "Manga" and taps its series "alpha".
  Future<void> openAlpha(WidgetTester tester, FakeServer server) async {
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
  }

  VoidCallback? reloadAction(WidgetTester tester) => tester
      .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh))
      .onPressed;

  testWidgets(
    'names each book by its volume and chapter, in the order the server sends',
    (tester) async {
      final server = alphaServer(
        () async => jsonAnswer([
          bookJson(7, volume: 1),
          bookJson(8, volume: 2, chapter: 13),
          bookJson(9, chapter: 12),
          bookJson(10, title: 'Extras'),
        ]),
      );
      await openAlpha(tester, server);
      await tester.pumpAndSettle();

      final names = [
        english.text('browse.volume', {'number': 1}),
        english.text('browse.volume_chapter', {'volume': 2, 'chapter': 13}),
        english.text('browse.chapter', {'number': 12}),
        'Extras',
      ];
      final places = [
        for (final name in names) tester.getTopLeft(find.text(name)),
      ];
      for (final (index, place) in places.indexed.skip(1)) {
        final before = places[index - 1];
        expect(
          place.dy > before.dy ||
              (place.dy == before.dy && place.dx > before.dx),
          isTrue,
          reason: '"${names[index]}" comes after "${names[index - 1]}"',
        );
      }
      expect(find.widgetWithText(AppBar, 'alpha'), findsOneWidget);
      final request = server.requests.singleWhere(
        (request) => request.url.path == '/api/v1/series/4/books',
      );
      expect(request.method, 'GET');
      expect(request.headers['authorization'], 'Bearer session-1');
    },
  );

  testWidgets("shows each book's cover", (tester) async {
    final server = alphaServer(
      () async => jsonAnswer([bookJson(7, volume: 1), bookJson(8, volume: 2)]),
    );
    await openAlpha(tester, server);
    await tester.pumpAndSettle();

    expect(
      requestedCovers(server),
      containsAll(['/api/v1/covers/book/7', '/api/v1/covers/book/8']),
    );
  });

  testWidgets('says so when the series has no books', (tester) async {
    await openAlpha(tester, alphaServer(() async => jsonAnswer([])));
    await tester.pumpAndSettle();

    expect(find.text(english.text('browse.books_empty')), findsOneWidget);
  });

  testWidgets('shows progress while the books load', (tester) async {
    final answer = Completer<http.Response>();
    await openAlpha(tester, alphaServer(() => answer.future));
    await finishTransition(tester);

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(reloadAction(tester), isNull, reason: 'one load at a time');

    answer.complete(jsonAnswer([bookJson(7, volume: 1)]));
    await tester.pumpAndSettle();

    expect(
      find.text(english.text('browse.volume', {'number': 1})),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(reloadAction(tester), isNotNull);
  });

  testWidgets(
    'shows the reason the server gives for refusing, with Reload under it',
    (tester) async {
      var calls = 0;
      final server = alphaServer(
        () async => ++calls == 1
            ? jsonAnswer({'error': 'internal_error'}, 500)
            : jsonAnswer([bookJson(7, volume: 1)]),
      );
      await openAlpha(tester, server);
      await tester.pumpAndSettle();

      expect(find.text(english.text('errors.internal_error')), findsOneWidget);

      await tester.tap(
        find.widgetWithText(FilledButton, english.text('browse.reload')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(english.text('browse.volume', {'number': 1})),
        findsOneWidget,
      );
      expect(find.text(english.text('errors.internal_error')), findsNothing);
    },
  );

  testWidgets('Reload at the top loads the books again', (tester) async {
    var calls = 0;
    final server = alphaServer(
      () async => jsonAnswer([
        bookJson(7, volume: 1),
        if (++calls > 1) bookJson(8, volume: 2),
      ]),
    );
    await openAlpha(tester, server);
    await tester.pumpAndSettle();
    final volume2 = find.text(english.text('browse.volume', {'number': 2}));
    expect(volume2, findsNothing);

    await tester.tap(find.byTooltip(english.text('browse.reload')));
    await tester.pumpAndSettle();

    expect(volume2, findsOneWidget);
  });

  testWidgets('a tap on a book opens it in the reader for its format', (
    tester,
  ) async {
    await openAlpha(
      tester,
      alphaServer(
        () async => jsonAnswer([
          bookJson(7, volume: 1),
          bookJson(8, volume: 2, format: 'pdf'),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(cardNamed(english.text('browse.volume', {'number': 2})));
    await tester.pumpAndSettle();
    expect(find.text(english.text('reader.unsupported')), findsOneWidget);
    expect(find.byType(BooksScreen), findsOneWidget, reason: 'nothing opened');

    await tester.tap(cardNamed(english.text('browse.volume', {'number': 1})));
    await tester.pumpAndSettle();
    expect(find.byType(PageReader), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Alpha'), findsOneWidget);
  });
}
