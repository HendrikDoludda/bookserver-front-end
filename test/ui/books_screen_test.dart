import 'dart:async';
import 'dart:convert';

import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/books_screen.dart';
import 'package:bookserver/ui/cover_grid.dart';
import 'package:bookserver/ui/readers/page_reader.dart';
import 'package:bookserver/ui/settings_screen.dart';
import 'package:flutter/gestures.dart';
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

  /// A book exactly as `GET /api/v1/series/{id}/books` sends one, with the user's [progress] in
  /// it.
  Map<String, Object?> bookJson(
    int id, {
    String title = 'Alpha',
    int? volume,
    num? chapter,
    String format = 'cbz',
    Map<String, Object?> progress = const {
      'position': null,
      'total': null,
      'finished': false,
    },
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
    'progress': progress,
  };

  /// A server with the library "Manga" (id 3), its one series "alpha" (id 4), and that series'
  /// books from [answer]; a book marked read or unread goes to [mark]. Nothing has a cover.
  FakeServer alphaServer(
    Future<http.Response> Function() answer, {
    Future<http.Response> Function(http.Request request)? mark,
  }) => bookServer(
    (request) => switch (request.url.path) {
      '/api/v1/libraries' => Future.value(
        jsonAnswer([
          {'id': 3, 'name': 'Manga', 'series_count': 1},
        ]),
      ),
      '/api/v1/libraries/3/series' => Future.value(
        jsonAnswer([
          {'id': 4, 'name': 'alpha', 'book_count': 1},
        ]),
      ),
      '/api/v1/series/4/books' => answer(),
      final path when mark != null && path.endsWith('/progress') => mark(
        request,
      ),
      _ => Future.value(notFound()),
    },
  );

  String volume(int number) =>
      english.text('browse.volume', {'number': number});

  /// The books list's loads [server] got.
  int bookLoads(FakeServer server) => server.requests
      .where((request) => request.url.path == '/api/v1/series/4/books')
      .length;

  Finder onCard(String name, Finder finder) =>
      find.descendant(of: cardNamed(name), matching: finder);

  /// Starts the app signed in, opens the library "Manga" and taps its series "alpha".
  Future<void> openAlpha(
    WidgetTester tester,
    FakeServer server, {
    Catalog? catalog,
  }) async {
    await pumpApp(
      tester,
      catalog: catalog ?? english,
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

  testWidgets('a decimal chapter is named as the language writes numbers', (
    tester,
  ) async {
    final german = Catalog.fromJson(
      {
        'browse': {'chapter': 'Kapitel {number}'},
      },
      language: 'de',
      fallback: english,
    );
    final server = alphaServer(
      () async => jsonAnswer([bookJson(7, chapter: 1.5)]),
    );

    await openAlpha(tester, server, catalog: german);
    await tester.pumpAndSettle();

    expect(find.text('Kapitel 1,5'), findsOneWidget);
  });

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

  testWidgets("a book's card has nothing under its name", (tester) async {
    final server = alphaServer(
      () async => jsonAnswer([bookJson(7, volume: 1)]),
    );
    await openAlpha(tester, server);
    await tester.pumpAndSettle();

    Finder onBooksScreen(Type type) => find.descendant(
      of: find.byType(BooksScreen),
      matching: find.byType(type),
    );
    expect(tester.widget<CoverCard>(onBooksScreen(CoverCard)).detail, isNull);
    expect(
      tester.widget<CoverGrid>(onBooksScreen(CoverGrid)).withDetail,
      isFalse,
      reason: 'no room kept for a line that never shows',
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

  testWidgets('the user menu opens Settings and signs out', (tester) async {
    await openAlpha(tester, alphaServer(() async => jsonAnswer([])));
    await tester.pumpAndSettle();

    await chooseInUserMenu(tester, english, 'menu.settings');
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(BooksScreen), findsOneWidget);

    await chooseInUserMenu(tester, english, 'menu.sign_out');
    await tester.pumpAndSettle();
    expect(find.text(english.text('login.username_or_email')), findsOneWidget);
  });

  testWidgets('a tap on a book opens it in the reader for its format', (
    tester,
  ) async {
    await openAlpha(
      tester,
      alphaServer(
        () async => jsonAnswer([
          bookJson(7, volume: 1),
          bookJson(8, volume: 2, format: 'mobi'),
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

  testWidgets('a started book shows a bar, a finished one a check', (
    tester,
  ) async {
    await openAlpha(
      tester,
      alphaServer(
        () async => jsonAnswer([
          bookJson(
            7,
            volume: 1,
            progress: {'position': 3, 'total': 10, 'finished': false},
          ),
          bookJson(
            8,
            volume: 2,
            progress: {'position': 9, 'total': 10, 'finished': true},
          ),
          bookJson(9, volume: 3),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    final bar = find.byType(LinearProgressIndicator);
    final check = find.byIcon(Icons.check_circle);
    expect(
      tester.widget<LinearProgressIndicator>(onCard(volume(1), bar)).value,
      0.4,
      reason: 'page 4 of 10 on screen',
    );
    expect(onCard(volume(1), check), findsNothing);
    expect(onCard(volume(2), check), findsOneWidget);
    expect(onCard(volume(2), bar), findsNothing);
    expect(onCard(volume(3), bar), findsNothing);
    expect(onCard(volume(3), check), findsNothing);
  });

  testWidgets(
    'a long press marks a book read, and the list shows it, kept on screen',
    (tester) async {
      var finished = false;
      final marked = Completer<http.Response>();
      final marks = <http.Request>[];
      final server = alphaServer(
        () async => jsonAnswer([
          bookJson(
            7,
            volume: 1,
            progress: {'position': 3, 'total': 10, 'finished': finished},
          ),
        ]),
        mark: (request) {
          marks.add(request);
          return marked.future;
        },
      );
      await openAlpha(tester, server);
      await tester.pumpAndSettle();

      await tester.longPress(cardNamed(volume(1)));
      await tester.pumpAndSettle();
      expect(find.text(english.text('browse.mark_unread')), findsNothing);
      await tester.tap(find.text(english.text('browse.mark_read')));
      await tester.pumpAndSettle();

      final request = marks.single;
      expect(request.method, 'PATCH');
      expect(request.url.path, '/api/v1/books/7/progress');
      expect(jsonDecode(request.body), {'finished': true});
      finished = true;
      marked.complete(
        jsonAnswer({'position': 3, 'total': 10, 'finished': true}),
      );
      await tester.pump();
      expect(cardNamed(volume(1)), findsOneWidget, reason: 'while it reloads');
      await tester.pumpAndSettle();

      expect(bookLoads(server), 2);
      expect(
        onCard(volume(1), find.byIcon(Icons.check_circle)),
        findsOneWidget,
      );
    },
  );

  testWidgets('a finished book offers to mark it unread', (tester) async {
    final marks = <Object?>[];
    final server = alphaServer(
      () async => jsonAnswer([
        bookJson(
          7,
          volume: 1,
          progress: {'position': 9, 'total': 10, 'finished': true},
        ),
      ]),
      mark: (request) async {
        marks.add(jsonDecode(request.body));
        return jsonAnswer({'position': 9, 'total': 10, 'finished': false});
      },
    );
    await openAlpha(tester, server);
    await tester.pumpAndSettle();

    await tester.tap(cardNamed(volume(1)), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text(english.text('browse.mark_read')), findsNothing);
    await tester.tap(find.text(english.text('browse.mark_unread')));
    await tester.pumpAndSettle();

    expect(marks, [
      {'finished': false},
    ]);
  });

  testWidgets('a mark the server refuses says so, and loads nothing again', (
    tester,
  ) async {
    final server = alphaServer(
      () async => jsonAnswer([bookJson(7, volume: 1)]),
      mark: (_) async => jsonAnswer({'error': 'internal_error'}, 500),
    );
    await openAlpha(tester, server);
    await tester.pumpAndSettle();

    await tester.longPress(cardNamed(volume(1)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(english.text('browse.mark_read')));
    await tester.pumpAndSettle();

    expect(find.text(english.text('browse.mark_not_saved')), findsOneWidget);
    expect(bookLoads(server), 1);
  });

  testWidgets('the books load again when the reader closes', (tester) async {
    final server = alphaServer(
      () async => jsonAnswer([bookJson(7, volume: 1)]),
    );
    await openAlpha(tester, server);
    await tester.pumpAndSettle();

    await tester.tap(cardNamed(volume(1)));
    await tester.pumpAndSettle();
    expect(find.byType(PageReader), findsOneWidget);
    expect(bookLoads(server), 1);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(BooksScreen), findsOneWidget);
    expect(bookLoads(server), 2);
  });
}
