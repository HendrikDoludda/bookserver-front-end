import 'dart:async';
import 'dart:io';

import 'package:bookserver/data/api_client.dart';
import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_http_client.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/home_screen.dart';
import 'package:bookserver/ui/readers/open_book.dart';
import 'package:bookserver/ui/readers/pdf_reader.dart';
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
  /// answers a range request for the book's file.
  Future<FakeServer> openReader(WidgetTester tester) async {
    final server = bookServer(
      (request) async => switch (request.url.path) {
        '/api/v1/libraries' => jsonAnswer([]),
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

  test('the viewer renders two window heights above and below the screen, measures pages as they '
      'come, and draws full detail once scrolling pauses', () {
    const background = Color(0xFF808080);
    final params = pdfViewerParams(
      background: background,
      onPageChanged: (_) {},
      onTap: () {},
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
        background: const Color(0xFF808080),
        onPageChanged: (_) {},
        onTap: () => taps++,
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
      background: const Color(0xFF808080),
      onPageChanged: (_) {},
      onTap: () {},
      onInteractionStart: () => starts++,
    );

    params.onInteractionStart!(ScaleStartDetails());

    expect(starts, 1);
  });
}
