import 'dart:async';
import 'dart:io';

import 'package:bookserver/data/api_client.dart';
import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_http_client.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/home_screen.dart';
import 'package:bookserver/ui/readers/open_book.dart';
import 'package:bookserver/ui/readers/pdf_reader.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../support/fake_pdf_engine.dart';
import '../../support/fake_server.dart';
import '../../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });

  late FakePdfEngine engine;
  late Directory temp;
  setUp(() {
    engine = FakePdfEngine();
    PdfrxEntryFunctions.instance = engine;
    temp = Directory.systemTemp.createTempSync('bookserver-pdf-');
    Pdfrx.cacheDirectoryPath = temp.path;
    Pdfrx.createHttpClient = null;
  });
  tearDown(() => temp.deleteSync(recursive: true));

  const book = Book(
    id: 7,
    title: 'A throne stolen',
    format: BookFormat.pdf,
    volume: 1,
  );

  Directory blockCache() => Directory('${temp.path}/pdfrx.cache');

  /// Leaves a file where pdfrx keeps the blocks it has downloaded.
  void leaveBlocks() =>
      File('${blockCache().path}/ab/cd/blocks.pdf').createSync(recursive: true);

  /// Starts the app signed in and opens the book the way a tap on its card does; the server
  /// answers a range request for the book's file, and for the book itself with [details]: by
  /// default, read in continuous scroll.
  Future<FakeServer> openReader(
    WidgetTester tester, {
    Future<http.Response> Function()? details,
  }) async {
    final server = bookServer(
      (request) async => switch (request.url.path) {
        '/api/v1/libraries' => jsonAnswer([]),
        '/api/v1/books/7' =>
          await (details?.call() ??
              Future.value(
                jsonAnswer({'series': 3, 'reading_mode': 'continuous'}),
              )),
        '/api/v1/books/7/file' => http.Response(
          '%PDF',
          206,
          headers: {'content-range': 'bytes 0-3/1000'},
        ),
        _ => notFound(),
      },
    );
    final session = await pumpApp(
      tester,
      catalog: english,
      store: signedInStore(),
      server: server,
    );
    await tester.pumpAndSettle();
    openBook(tester.element(find.byType(HomeScreen)), session, book);
    await finishTransition(tester);
    return server;
  }

  testWidgets(
    "opens the book's file in byte ranges, page by page, with the app's timeout",
    (tester) async {
      await openReader(tester);

      final open = engine.opens.single;
      expect(open.uri, testOrigin.resolve(bookFilePath(7)));
      expect(open.rangeAccess, isTrue);
      expect(open.progressive, isTrue);
      expect(open.timeout, ApiClient.defaultTimeout);
      expect(find.widgetWithText(AppBar, 'A throne stolen'), findsOneWidget);
      expect(find.text(english.text('reader.opening')), findsOneWidget);
    },
  );

  testWidgets('pdfrx downloads through the session', (tester) async {
    final server = await openReader(tester);

    final client = Pdfrx.createHttpClient!();
    expect(client, isA<SessionHttpClient>());
    final response = await client.send(
      http.Request('GET', testOrigin.resolve(bookFilePath(7)))
        ..headers['Range'] = 'bytes=0-3',
    );

    expect(response.statusCode, 206);
    expect(server.requests.last.headers['authorization'], 'Bearer session-1');
    expect(server.requests.last.headers['range'], 'bytes=0-3');
  });

  testWidgets("a book that can't be opened says so; Try again opens it again", (
    tester,
  ) async {
    await openReader(tester);
    final openFailed = find.text(english.text('reader.open_failed'));
    final retry = find.widgetWithText(
      FilledButton,
      english.text('reader.retry'),
    );

    engine.opens.single.answer.completeError(
      const PdfException('Failed to download PDF file'),
    );
    await tester.pump();
    expect(openFailed, findsOneWidget);

    await tester.tap(retry);
    await tester.pump();
    expect(engine.opens, hasLength(2));
    expect(find.text(english.text('reader.opening')), findsOneWidget);

    engine.opens.last.answer.completeError(TimeoutException('no answer'));
    await tester.pump();
    expect(openFailed, findsOneWidget, reason: 'any failure says the same');
  });

  testWidgets(
    'downloaded blocks go before a book opens and after its reader closes',
    (tester) async {
      leaveBlocks();
      await openReader(tester);
      expect(
        blockCache().existsSync(),
        isFalse,
        reason: 'gone before the open',
      );

      leaveBlocks();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(
        blockCache().existsSync(),
        isFalse,
        reason: 'gone after the close',
      );
    },
  );

  testWidgets('asks for the mode while the document opens, with the session', (
    tester,
  ) async {
    final server = await openReader(tester);

    expect(engine.opens, hasLength(1));
    final asked = [
      for (final request in server.requests)
        if (request.url.path == '/api/v1/books/7') request,
    ];
    expect(asked, hasLength(1), reason: 'before the document has opened');
    expect(asked.single.headers['authorization'], 'Bearer session-1');
    expect(find.text(english.text('reader.opening')), findsOneWidget);
  });

  testWidgets(
    "a mode that didn't load says the book can't be opened; Try again asks again",
    (tester) async {
      var asks = 0;
      await openReader(
        tester,
        details: () async {
          asks++;
          return http.Response('', 503);
        },
      );
      await tester.pump();

      expect(
        find.text(english.text('reader.open_failed')),
        findsOneWidget,
        reason: 'while the document is still opening',
      );
      expect(find.byTooltip(english.text('reader.mode')), findsNothing);

      await tester.tap(
        find.widgetWithText(FilledButton, english.text('reader.retry')),
      );
      await tester.pump();
      expect(engine.opens, hasLength(2));
      expect(asks, 2);
    },
  );

  /// The viewer's settings for [mode]; its turns go to [turns], its taps to [onTap].
  PdfViewerParams paramsFor(
    ReadingMode mode, {
    List<int>? turns,
    VoidCallback? onTap,
  }) => pdfViewerParams(
    mode: mode,
    background: const Color(0xFF808080),
    onPageChanged: (_) {},
    onTap: onTap ?? () {},
    onTurn: turns?.add ?? (_) {},
    onInteractionStart: () {},
  );

  test('scrolls one column, or shows one page at a time fitted to the window, either way', () {
    final continuous = paramsFor(ReadingMode.continuous);
    expect(continuous.layoutStrategy, const SequentialPagesLayout());
    expect(continuous.paging, isNull);
    expect(continuous.calculateCurrentPageNumber, isNull);

    final leftToRight = paramsFor(ReadingMode.ltr);
    expect(
      leftToRight.layoutStrategy,
      const SequentialPagesLayout(
        scrollDirection: Axis.horizontal,
        fitMode: PdfFitMode.fit,
      ),
    );
    expect(leftToRight.paging, const PdfPaging());
    expect(leftToRight.calculateCurrentPageNumber, isNull);

    final rightToLeft = paramsFor(ReadingMode.rtl);
    expect(rightToLeft.layoutStrategy, const RightToLeftPagesLayout());
    expect(rightToLeft.paging, const PdfPaging());
    expect(rightToLeft.calculateCurrentPageNumber, mostVisiblePage);

    for (final mode in ReadingMode.values) {
      expect(
        paramsFor(mode).keyHandlerParams.autofocus,
        isTrue,
        reason: '$mode',
      );
    }
  });

  test("in a paged mode the arrow keys turn the pages by the side they lie on; scrolling keeps pdfrx's keys", () {
    const keys = PdfViewerKeyHandlerParams();
    for (final (mode, left, right) in [
      (ReadingMode.ltr, -1, 1),
      (ReadingMode.rtl, 1, -1),
    ]) {
      final turns = <int>[];
      final onKey = paramsFor(mode, turns: turns).onKey!;

      expect(onKey(keys, LogicalKeyboardKey.arrowLeft, true), isTrue);
      expect(
        onKey(keys, LogicalKeyboardKey.arrowRight, false),
        isTrue,
        reason: 'a key held down turns on',
      );
      expect(
        onKey(keys, LogicalKeyboardKey.arrowDown, true),
        isNull,
        reason: "pdfrx's own",
      );
      expect(turns, [left, right], reason: '$mode');
    }
    expect(paramsFor(ReadingMode.continuous).onKey, isNull);
  });

  testWidgets("in a paged mode a tap on an outer third turns the page and one in the middle is the reader's; "
      "scrolling, every tap is the reader's", (tester) async {
    await tester.pumpWidget(
      const Center(child: SizedBox(width: 600, height: 400)),
    );
    final context = tester.element(find.byType(SizedBox));
    bool tapAt(PdfViewerParams params, double dx) => params.onGeneralTap!(
      context,
      PdfViewerController(),
      PdfViewerGeneralTapHandlerDetails(
        localPosition: Offset(dx, 200),
        documentPosition: Offset.zero,
        type: PdfViewerGeneralTapType.tap,
        tapOn: PdfViewerPart.background,
      ),
    );

    for (final (mode, expected) in [
      (ReadingMode.ltr, [-1, 1]),
      (ReadingMode.rtl, [1, -1]),
      (ReadingMode.continuous, <int>[]),
    ]) {
      final turns = <int>[];
      var taps = 0;
      final params = paramsFor(mode, turns: turns, onTap: () => taps++);

      for (final dx in [50.0, 550.0, 300.0]) {
        expect(tapAt(params, dx), isTrue, reason: '$mode at $dx');
      }
      expect(turns, expected, reason: '$mode');
      expect(taps, expected.isEmpty ? 3 : 1, reason: '$mode');
    }
  });

  test('right to left, page 1 lies at the right end, each page in a slot one window wide, the slots '
      'listed as they lie', () {
    final context = PdfPageLayoutContext(
      pages: [_Page(600, 800), _Page(800, 600), _Page(600, 900)],
      viewport: const Size(400, 600),
      paged: true,
    );
    final layout = const RightToLeftPagesLayout().resolve(context);
    final leftToRight = const SequentialPagesLayout(
      scrollDirection: Axis.horizontal,
      fitMode: PdfFitMode.fit,
    ).resolve(context);

    expect(layout.documentSize, const Size(1200, 600));
    expect(layout.effectivePrimaryAxis, Axis.horizontal);
    for (final (index, page) in layout.pageLayouts.indexed) {
      final mirrored = leftToRight.pageLayouts[index];
      expect(page.left, moreOrLessEquals(1200 - mirrored.right));
      expect(page.width, moreOrLessEquals(mirrored.width));
      expect((page.top, page.height), (mirrored.top, mirrored.height));
    }
    expect(layout.spreads, const [
      PdfPageRange.single(3),
      PdfPageRange.single(2),
      PdfPageRange.single(1),
    ]);
    for (final (index, (left, right)) in [
      (0.0, 400.0),
      (400.0, 800.0),
      (800.0, 1200.0),
    ].indexed) {
      final slot = layout.spreadSlots[index];
      expect(slot.left, moreOrLessEquals(left), reason: 'slot $index');
      expect(slot.right, moreOrLessEquals(right), reason: 'slot $index');
      final page = layout.spreads[index].firstPageNumber;
      expect(slot.contains(layout.pageLayouts[page - 1].center), isTrue);
    }
    expect(
      [for (var page = 0; page <= 4; page++) layout.spreadIndexOf(page)],
      [-1, 2, 1, 0, -1],
    );
  });

  test(
    "the page on screen is the one that takes up most of the window's width",
    () {
      const pages = [
        Rect.fromLTWH(800, 0, 400, 600),
        Rect.fromLTWH(400, 0, 400, 600),
        Rect.fromLTWH(0, 0, 400, 600),
      ];
      final controller = PdfViewerController();

      for (final (left, page) in [
        (800.0, 1),
        (500.0, 2),
        (100.0, 3),
        (1300.0, null),
      ]) {
        expect(
          mostVisiblePage(Rect.fromLTWH(left, 0, 400, 600), pages, controller),
          page,
          reason: '$left',
        );
      }
    },
  );

  test('the viewer renders two window heights above and below the screen, measures pages as they '
      'come, and draws full detail once scrolling pauses', () {
    const background = Color(0xFF808080);
    final params = pdfViewerParams(
      mode: ReadingMode.continuous,
      background: background,
      onPageChanged: (_) {},
      onTap: () {},
      onTurn: (_) {},
      onInteractionStart: () {},
    );

    expect(params.verticalCacheExtent, 2);
    expect(params.behaviorControlParams.loadPageDimensionsOnDemand, isTrue);
    expect(
      params.behaviorControlParams.partialImageLoadingDelay,
      const Duration(milliseconds: 300),
    );
    expect(params.backgroundColor, background);
  });

  testWidgets(
    'a single tap on the pages is the reader\'s; the viewer keeps the rest',
    (tester) async {
      var taps = 0;
      final params = pdfViewerParams(
        mode: ReadingMode.continuous,
        background: const Color(0xFF808080),
        onPageChanged: (_) {},
        onTap: () => taps++,
        onTurn: (_) {},
        onInteractionStart: () {},
      );
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));

      bool tap(PdfViewerGeneralTapType type) => params.onGeneralTap!(
        context,
        PdfViewerController(),
        PdfViewerGeneralTapHandlerDetails(
          localPosition: Offset.zero,
          documentPosition: Offset.zero,
          type: type,
          tapOn: PdfViewerPart.background,
        ),
      );

      expect(tap(PdfViewerGeneralTapType.tap), isTrue);
      expect(taps, 1);
      for (final type in [
        PdfViewerGeneralTapType.doubleTap,
        PdfViewerGeneralTapType.longPress,
        PdfViewerGeneralTapType.secondaryTap,
      ]) {
        expect(tap(type), isFalse, reason: '$type');
      }
      expect(taps, 1);
    },
  );

  test('the start of a drag or a pinch is reported', () {
    var starts = 0;
    final params = pdfViewerParams(
      mode: ReadingMode.continuous,
      background: const Color(0xFF808080),
      onPageChanged: (_) {},
      onTap: () {},
      onTurn: (_) {},
      onInteractionStart: () => starts++,
    );

    params.onInteractionStart!(ScaleStartDetails());

    expect(starts, 1);
  });
}

/// A page of [width] × [height] points: all a layout reads of one.
class _Page implements PdfPage {
  _Page(this.width, this.height);

  @override
  final double width;

  @override
  final double height;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
