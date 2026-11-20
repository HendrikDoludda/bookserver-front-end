import 'dart:async';
import 'dart:convert';

import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/home_screen.dart';
import 'package:bookserver/ui/readers/open_book.dart';
import 'package:bookserver/ui/readers/page_column.dart';
import 'package:bookserver/ui/readers/page_turner.dart';
import 'package:bookserver/ui/readers/reader_frame.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../../support/fake_server.dart';
import '../../support/images.dart';
import '../../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });
  // Every test asks the same server for the same pages: none may come from a test before.
  setUp(() => PaintingBinding.instance.imageCache.clear());

  const book = Book(
    id: 7,
    title: 'Demo Comic',
    format: BookFormat.cbz,
    volume: 1,
  );

  http.Response pageList(int count) => jsonAnswer([
    for (var number = 1; number <= count; number++)
      {'number': number, 'width': 1200, 'height': 1800},
  ]);

  /// Book 7 as `GET /api/v1/books/7` answers it: read in [mode], part of [series].
  http.Response details({String mode = 'ltr', int? series = 3}) => jsonAnswer({
    'id': 7,
    'title': 'Demo Comic',
    'format': 'cbz',
    'series': series,
    'reading_mode': mode,
  });

  /// A server without libraries, whose book 7 lists its pages with [pages], answers for itself
  /// with [book] and answers page n with [page]; without [page], no page exists. A mode saved for
  /// series 3 goes to [save], which takes it by default.
  FakeServer readerServer(
    Future<http.Response> Function() pages, {
    Future<http.Response> Function(int number)? page,
    Future<http.Response> Function()? book,
    Future<http.Response> Function(http.Request request)? save,
  }) => bookServer((request) {
    final path = request.url.path;
    if (path == '/api/v1/libraries') {
      return Future.value(jsonAnswer([]));
    }
    if (path == '/api/v1/books/7') {
      return book?.call() ?? Future.value(details());
    }
    if (path == '/api/v1/series/3/reading_mode') {
      return save?.call(request) ??
          Future.value(jsonAnswer(jsonDecode(request.body)));
    }
    if (path == '/api/v1/books/7/pages') {
      return pages();
    }
    final number = RegExp(r'^/api/v1/books/7/pages/(\d+)$').firstMatch(path);
    if (number != null && page != null) {
      return page(int.parse(number[1]!));
    }
    return Future.value(notFound());
  });

  /// Starts the app signed in and opens the book the way a tap on its card does.
  Future<void> openReader(WidgetTester tester, FakeServer server) async {
    final session = await pumpApp(
      tester,
      catalog: english,
      store: signedInStore(),
      server: server,
    );
    await tester.pumpAndSettle();
    openBook(tester.element(find.byType(HomeScreen)), session, book);
    await finishTransition(tester);
  }

  /// Lets a page turn run to its end; pages still loading keep `pumpAndSettle` from returning.
  Future<void> finishTurn(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  String pageOf(int page, int count) =>
      english.text('reader.page_of', {'page': page, 'count': count});

  List<String> pagesAskedFor(FakeServer server) => [
    for (final path in requestedPaths(server))
      if (path.startsWith('/api/v1/books/7/pages/')) path,
  ];

  PageTurner turner(WidgetTester tester) =>
      tester.widget<PageTurner>(find.byType(PageTurner));

  /// Opens the reading-mode menu in the bar and chooses the mode named [key]: taps its entry, whose
  /// ink layer lies over its name.
  Future<void> chooseMode(WidgetTester tester, String key) async {
    await tester.tap(find.byTooltip(english.text('reader.mode')));
    await finishTurn(tester);
    await tester.tap(
      find.ancestor(
        of: find.text(english.text(key)),
        matching: find.byWidgetPredicate(
          (widget) => widget is CheckedPopupMenuItem<ReadingMode>,
        ),
      ),
    );
    await finishTurn(tester);
  }

  /// Brings back the bars a turn or a scroll hid: a tap in the middle of the pages [pages] shows,
  /// above the notice a page that didn't load shows.
  Future<void> showBars(WidgetTester tester, Finder pages) async {
    final area = tester.getRect(pages);
    await tester.tapAt(Offset(area.center.dx, area.top + area.height / 4));
    await finishTurn(tester);
    expect(
      tester.state<ReaderFrameState>(find.byType(ReaderFrame)).barShown,
      isTrue,
    );
  }

  /// The column's own scrolling, the outermost in it: a page's notice scrolls as well.
  ScrollPosition columnScroll(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(PageColumn),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  testWidgets("opens on the first page, under the book's title", (
    tester,
  ) async {
    final server = readerServer(() async => pageList(3));
    await openReader(tester, server);

    expect(find.widgetWithText(AppBar, 'Demo Comic'), findsOneWidget);
    expect(find.text(pageOf(1, 3)), findsOneWidget);
    expect(find.widgetWithIcon(IconButton, Icons.refresh), findsNothing);
    final request = server.requests.singleWhere(
      (request) => request.url.path == '/api/v1/books/7/pages',
    );
    expect(request.headers['authorization'], 'Bearer session-1');
  });

  testWidgets('loads the page on screen and the next one, with the session', (
    tester,
  ) async {
    final server = readerServer(() async => pageList(3));
    await openReader(tester, server);

    expect(
      pagesAskedFor(server),
      unorderedEquals(['/api/v1/books/7/pages/1', '/api/v1/books/7/pages/2']),
    );
    for (final request in server.requests) {
      expect(request.headers['authorization'], 'Bearer session-1');
    }
  });

  testWidgets("decodes a page no wider than twice the window's shorter side", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await openReader(tester, readerServer(() async => pageList(1)));

    expect(
      tester.widget<Image>(find.byType(Image)).image,
      isA<ResizeImage>().having((image) => image.width, 'width', 2340),
    );
  });

  testWidgets('the arrow keys turn the pages, never past either end', (
    tester,
  ) async {
    final server = readerServer(() async => pageList(3));
    await openReader(tester, server);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await finishTurn(tester);
    expect(find.text(pageOf(1, 3)), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await finishTurn(tester);
    expect(find.text(pageOf(2, 3)), findsOneWidget);
    expect(pagesAskedFor(server), contains('/api/v1/books/7/pages/3'));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await finishTurn(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await finishTurn(tester);
    expect(find.text(pageOf(3, 3)), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await finishTurn(tester);
    expect(find.text(pageOf(2, 3)), findsOneWidget);
  });

  testWidgets('a swipe turns the page', (tester) async {
    await openReader(tester, readerServer(() async => pageList(3)));

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await finishTurn(tester);

    expect(find.text(pageOf(2, 3)), findsOneWidget);
  });

  testWidgets('a zoomed page holds still under a swipe; a turn zooms out', (
    tester,
  ) async {
    await openReader(tester, readerServer(() async => pageList(3)));
    final zoom = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    zoom.value = Matrix4.diagonal3Values(2, 2, 1);
    await tester.pump();

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await finishTurn(tester);
    expect(find.text(pageOf(1, 3)), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await finishTurn(tester);
    expect(find.text(pageOf(2, 3)), findsOneWidget);
    expect(zoom.value.getMaxScaleOnAxis(), 1);
  });

  testWidgets(
    'a tap on the page shows and hides the bars; a turn hides them, the count stays',
    (tester) async {
      // No page loads, so each shows why: text to tap, with Try again under it.
      await openReader(tester, readerServer(() async => pageList(3)));
      await tester.pump();
      final frame = tester.state<ReaderFrameState>(find.byType(ReaderFrame));
      final onPage = find.text(english.text('reader.page_failed')).first;
      expect(frame.barShown, isTrue);

      await tester.tap(onPage);
      await finishTurn(tester);
      expect(frame.barShown, isFalse);

      await tester.tap(onPage);
      await finishTurn(tester);
      expect(frame.barShown, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await finishTurn(tester);
      expect(frame.barShown, isFalse);
      expect(find.text(pageOf(2, 3)), findsOneWidget);
    },
  );

  testWidgets("a page that didn't load says so, and Try again loads it", (
    tester,
  ) async {
    var tries = 0;
    final server = readerServer(
      () async => pageList(2),
      page: (number) async => switch (number) {
        1 when ++tries == 1 => jsonAnswer({'error': 'internal_error'}, 500),
        1 => http.Response.bytes(onePixelPng, 200),
        _ => notFound(),
      },
    );
    await openReader(tester, server);
    await tester.pump();
    expect(find.text(english.text('reader.page_failed')), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(
        find.widgetWithText(FilledButton, english.text('reader.retry')),
      );
      await tester.pump();
      await tester.pump();
      await loaded(tester.widget<Image>(find.byType(Image)).image);
    });
    await tester.pump();

    expect(find.text(english.text('reader.page_failed')), findsNothing);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(
      pagesAskedFor(server).where((path) => path.endsWith('/pages/1')),
      hasLength(2),
    );
  });

  testWidgets("a book without pages says it can't be opened", (tester) async {
    await openReader(tester, readerServer(() async => pageList(0)));

    expect(find.text(english.text('reader.open_failed')), findsOneWidget);
  });

  testWidgets(
    "a page list that didn't load says why, with Try again under it",
    (tester) async {
      var calls = 0;
      await openReader(
        tester,
        readerServer(
          () async => ++calls == 1 ? http.Response('', 503) : pageList(2),
        ),
      );
      expect(find.text(english.text('connection.unreachable')), findsOneWidget);

      await tester.tap(
        find.widgetWithText(FilledButton, english.text('reader.retry')),
      );
      await finishTurn(tester);

      expect(find.text(pageOf(1, 2)), findsOneWidget);
    },
  );

  testWidgets(
    'opens in the mode the server answers for the book, its button showing it',
    (tester) async {
      await openReader(
        tester,
        readerServer(
          () async => pageList(3),
          book: () async => details(mode: 'rtl'),
        ),
      );

      expect(turner(tester).rightToLeft, isTrue);
      expect(find.byIcon(Icons.west), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await finishTurn(tester);
      expect(
        find.text(pageOf(2, 3)),
        findsOneWidget,
        reason: 'right to left, the left arrow goes forward',
      );
    },
  );

  testWidgets('asks for the pages and the mode at once, with the session', (
    tester,
  ) async {
    final pages = Completer<http.Response>();
    final server = readerServer(() => pages.future);
    await openReader(tester, server);

    expect(
      requestedPaths(server),
      containsAll(['/api/v1/books/7/pages', '/api/v1/books/7']),
      reason: 'the mode is asked for while the pages are on their way',
    );
    expect(find.text(english.text('reader.opening')), findsOneWidget);

    pages.complete(pageList(3));
    await finishTurn(tester);
    expect(find.text(pageOf(1, 3)), findsOneWidget);
    for (final request in server.requests) {
      expect(request.headers['authorization'], 'Bearer session-1');
    }
  });

  testWidgets(
    'a mode this version of the app does not know reads left to right',
    (tester) async {
      await openReader(
        tester,
        readerServer(
          () async => pageList(3),
          book: () async => details(mode: 'webtoon'),
        ),
      );

      expect(turner(tester).rightToLeft, isFalse);
      expect(find.byIcon(Icons.east), findsOneWidget);
    },
  );

  testWidgets("a mode that didn't load says why, with Try again under it", (
    tester,
  ) async {
    var calls = 0;
    await openReader(
      tester,
      readerServer(
        () async => pageList(2),
        book: () async =>
            ++calls == 1 ? http.Response('', 503) : details(mode: 'rtl'),
      ),
    );
    expect(find.text(english.text('connection.unreachable')), findsOneWidget);
    expect(find.byTooltip(english.text('reader.mode')), findsNothing);

    await tester.tap(
      find.widgetWithText(FilledButton, english.text('reader.retry')),
    );
    await finishTurn(tester);

    expect(find.text(pageOf(1, 2)), findsOneWidget);
    expect(turner(tester).rightToLeft, isTrue);
  });

  testWidgets(
    'the mode menu offers the three modes, the one on screen checked',
    (tester) async {
      await openReader(tester, readerServer(() async => pageList(3)));

      await tester.tap(find.byTooltip(english.text('reader.mode')));
      await finishTurn(tester);

      final items = tester.widgetList<CheckedPopupMenuItem<ReadingMode>>(
        find.byWidgetPredicate(
          (widget) => widget is CheckedPopupMenuItem<ReadingMode>,
        ),
      );
      expect(
        [for (final item in items) (item.value, item.checked)],
        [
          (ReadingMode.rtl, false),
          (ReadingMode.ltr, true),
          (ReadingMode.continuous, false),
        ],
      );
      for (final key in [
        'reader.mode_rtl',
        'reader.mode_ltr',
        'reader.mode_continuous',
      ]) {
        expect(find.text(english.text(key)), findsOneWidget, reason: key);
      }
    },
  );

  testWidgets(
    'a mode chosen shows at once, keeps the page, and is saved for the series',
    (tester) async {
      final saves = <http.Request>[];
      final saved = Completer<http.Response>();
      await openReader(
        tester,
        readerServer(
          () async => pageList(3),
          save: (request) {
            saves.add(request);
            return saved.future;
          },
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await finishTurn(tester);
      expect(find.text(pageOf(2, 3)), findsOneWidget);
      await showBars(tester, find.byType(PageTurner));

      await chooseMode(tester, 'reader.mode_rtl');

      expect(turner(tester).rightToLeft, isTrue, reason: 'before the save');
      expect(find.byIcon(Icons.west), findsOneWidget);
      expect(find.text(pageOf(2, 3)), findsOneWidget);
      final request = saves.single;
      expect(request.method, 'PUT');
      expect(request.headers['authorization'], 'Bearer session-1');
      expect(jsonDecode(request.body), {'mode': 'rtl'});

      saved.complete(jsonAnswer({'mode': 'rtl'}));
      await finishTurn(tester);
      expect(find.text(english.text('reader.mode_not_saved')), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await finishTurn(tester);
      expect(
        find.text(pageOf(3, 3)),
        findsOneWidget,
        reason: 'the keys still reach the pages, now right to left',
      );
    },
  );

  testWidgets('a refused save keeps the mode on screen and says so', (
    tester,
  ) async {
    await openReader(
      tester,
      readerServer(
        () async => pageList(3),
        save: (_) async => jsonAnswer({'error': 'internal_error'}, 500),
      ),
    );

    await chooseMode(tester, 'reader.mode_rtl');

    expect(find.text(english.text('reader.mode_not_saved')), findsOneWidget);
    expect(turner(tester).rightToLeft, isTrue);
  });

  testWidgets('a book outside any series switches without saving', (
    tester,
  ) async {
    final server = readerServer(
      () async => pageList(3),
      book: () async => details(series: null),
    );
    await openReader(tester, server);

    await chooseMode(tester, 'reader.mode_rtl');

    expect(turner(tester).rightToLeft, isTrue);
    expect([
      for (final path in requestedPaths(server))
        if (path.endsWith('/reading_mode')) path,
    ], isEmpty);
  });

  testWidgets('right to left, the left edge of a page goes forward', (
    tester,
  ) async {
    await openReader(
      tester,
      readerServer(
        () async => pageList(3),
        book: () async => details(mode: 'rtl'),
      ),
    );
    final pages = tester.getRect(find.byType(PageTurner));

    await tester.tapAt(pages.centerLeft + const Offset(20, 0));
    await finishTurn(tester);
    expect(find.text(pageOf(2, 3)), findsOneWidget);

    await tester.tapAt(pages.centerRight - const Offset(20, 0));
    await finishTurn(tester);
    expect(find.text(pageOf(1, 3)), findsOneWidget);
  });

  testWidgets(
    'continuous scroll takes over at the page on screen, and the pages take over from it',
    (tester) async {
      await openReader(tester, readerServer(() async => pageList(3)));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await finishTurn(tester);
      await showBars(tester, find.byType(PageTurner));

      await chooseMode(tester, 'reader.mode_continuous');

      expect(find.byType(PageColumn), findsOneWidget);
      expect(find.byType(PageTurner), findsNothing);
      expect(find.byType(InteractiveViewer), findsNothing, reason: 'no zoom');
      expect(find.byIcon(Icons.south), findsOneWidget);
      expect(find.text(pageOf(2, 3)), findsOneWidget);

      columnScroll(tester).jumpTo(columnScroll(tester).maxScrollExtent);
      await finishTurn(tester);
      expect(
        find.text(pageOf(3, 3)),
        findsOneWidget,
        reason: 'the page in the middle of the screen',
      );

      await showBars(tester, find.byType(PageColumn));
      await chooseMode(tester, 'reader.mode_ltr');
      expect(find.byType(PageTurner), findsOneWidget);
      expect(find.text(pageOf(3, 3)), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await finishTurn(tester);
      expect(find.text(pageOf(2, 3)), findsOneWidget);
    },
  );

  testWidgets('the keys scroll the column as soon as it shows', (tester) async {
    await openReader(tester, readerServer(() async => pageList(3)));

    await chooseMode(tester, 'reader.mode_continuous');
    final before = columnScroll(tester).pixels;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await finishTurn(tester);

    expect(columnScroll(tester).pixels, greaterThan(before));
  });

  testWidgets('a book read in continuous scroll opens in its column; a scroll hides the bars, a tap '
      'shows them', (tester) async {
    await openReader(
      tester,
      readerServer(
        () async => pageList(3),
        book: () async => details(mode: 'continuous'),
      ),
    );
    final frame = tester.state<ReaderFrameState>(find.byType(ReaderFrame));
    expect(find.byType(PageColumn), findsOneWidget);
    expect(find.text(pageOf(1, 3)), findsOneWidget);
    expect(frame.barShown, isTrue);

    await tester.drag(find.byType(PageColumn), const Offset(0, -300));
    await finishTurn(tester);
    expect(frame.barShown, isFalse);

    await showBars(tester, find.byType(PageColumn));
  });

  testWidgets("the column's pages decode at the page turner's width", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await openReader(
      tester,
      readerServer(
        () async => pageList(1),
        book: () async => details(mode: 'continuous'),
      ),
    );

    expect(
      tester.widget<Image>(find.byType(Image)).image,
      isA<ResizeImage>().having((image) => image.width, 'width', 2340),
    );
  });
}
