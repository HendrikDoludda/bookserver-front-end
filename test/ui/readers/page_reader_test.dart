import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/home_screen.dart';
import 'package:bookserver/ui/readers/open_book.dart';
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
    for (var number = 1; number <= count; number++) {'number': number},
  ]);

  /// A server without libraries, whose book 7 lists its pages with [pages] and answers page n
  /// with [page]; without [page], no page exists.
  FakeServer readerServer(
    Future<http.Response> Function() pages, [
    Future<http.Response> Function(int number)? page,
  ]) => bookServer((request) {
    final path = request.url.path;
    if (path == '/api/v1/libraries') {
      return Future.value(jsonAnswer([]));
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

  testWidgets("a page that didn't load says so, and Try again loads it", (
    tester,
  ) async {
    var tries = 0;
    final server = readerServer(
      () async => pageList(2),
      (number) async => switch (number) {
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
}
