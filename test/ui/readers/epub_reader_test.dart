import 'dart:convert';
import 'dart:io';

import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/epub_image.dart';
import 'package:bookserver/ui/home_screen.dart';
import 'package:bookserver/ui/readers/open_book.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../support/epubs.dart';
import '../../support/fake_path_provider.dart';
import '../../support/fake_server.dart';
import '../../support/images.dart';
import '../../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });

  late Directory temp;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('bookserver-epub-');
    PathProviderPlatform.instance = FakePathProvider(temp.path);
    PaintingBinding.instance.imageCache.clear();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  const book = Book(id: 7, title: 'The Great Gatsby', format: BookFormat.epub);

  /// A flowing EPUB of two chapters: a titled section with a link, then a picture from the book
  /// and one from the internet.
  final gatsby = epubBytes({
    'META-INF/container.xml': containerXml(),
    'OEBPS/content.opf': packageXml(
      {'one': 'text/one.xhtml', 'two': 'text/two.xhtml'},
      ['one', 'two'],
    ),
    'OEBPS/text/one.xhtml': chapterXhtml(
      '<section title="Chapter 1"><h1>Chapter one</h1>'
      '<p>In my younger and more vulnerable years.</p>'
      '<p><a href="two.xhtml">On to chapter two</a></p></section>',
    ),
    'OEBPS/text/two.xhtml': chapterXhtml(
      '<h1>Chapter two</h1>'
      '<p><img src="../images/dish.png" alt="A dish"/></p>'
      '<p><img src="https://tracker.example/pixel.png" alt="A tracker"/></p>',
    ),
    'OEBPS/images/dish.png': onePixelPng,
  });

  http.Response file(List<int> bytes) => http.Response.bytes(
    bytes,
    200,
    headers: {'content-type': 'application/epub+zip'},
  );

  /// A server without libraries whose book 7 is the file [answer] gives.
  FakeServer fileServer(Future<http.Response> Function() answer) => bookServer(
    (request) => switch (request.url.path) {
      '/api/v1/libraries' => Future.value(jsonAnswer([])),
      '/api/v1/books/7/file' => answer(),
      _ => Future.value(notFound()),
    },
  );

  final firstChapter = find.textContaining('In my younger', findRichText: true);

  /// Runs [first], then lets the reader's file work — writing the download, reading the archive,
  /// decoding pictures — go on in real time until [shown] is on screen or a few seconds have
  /// passed. That work never finishes on the test's fake clock.
  Future<void> runUntil(
    WidgetTester tester,
    Finder shown, {
    Future<void> Function()? first,
  }) async {
    await tester.runAsync(() async {
      await first?.call();
      for (var tries = 0; tries < 100 && shown.evaluate().isEmpty; tries++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    });
    await tester.pump(const Duration(seconds: 1));
  }

  /// Starts the app signed in and opens the book the way a tap on its card does, until [shown].
  Future<void> openReader(
    WidgetTester tester,
    FakeServer server,
    Finder shown,
  ) async {
    final session = await pumpApp(
      tester,
      catalog: english,
      store: signedInStore(),
      server: server,
    );
    await tester.pumpAndSettle();
    await runUntil(
      tester,
      shown,
      first: () async =>
          openBook(tester.element(find.byType(HomeScreen)), session, book),
    );
  }

  testWidgets(
    'downloads the book through the session and shows its chapters in order',
    (tester) async {
      final server = fileServer(() async => file(gatsby));
      await openReader(tester, server, firstChapter);

      expect(find.widgetWithText(AppBar, 'The Great Gatsby'), findsOneWidget);
      final request = server.requests.singleWhere(
        (request) => request.url.path == '/api/v1/books/7/file',
      );
      expect(request.headers['authorization'], 'Bearer session-1');
      final one = tester.getTopLeft(
        find.textContaining('Chapter one', findRichText: true),
      );
      final two = tester.getTopLeft(
        find.textContaining('Chapter two', findRichText: true),
      );
      expect(two.dy, greaterThan(one.dy));
      expect(
        tester.takeException(),
        isNull,
        reason: 'a titled section and a link show without errors',
      );
    },
  );

  testWidgets('shows a picture from the book, and none from anywhere else', (
    tester,
  ) async {
    await openReader(
      tester,
      fileServer(() async => file(gatsby)),
      find.byWidgetPredicate(
        (widget) => widget is RawImage && widget.image != null,
      ),
    );

    final pictures = [
      for (final image in tester.widgetList<Image>(find.byType(Image)))
        image.image,
    ];
    expect(pictures, hasLength(1));
    expect(
      (pictures.single as ResizeImage).imageProvider,
      isA<EpubImage>().having(
        (image) => image.path,
        'path',
        'OEBPS/images/dish.png',
      ),
    );
  });

  testWidgets("a file that is no EPUB says so; Try again downloads it again", (
    tester,
  ) async {
    var downloads = 0;
    final server = fileServer(
      () async => ++downloads == 1
          ? file(utf8.encode('plain text, no zip'))
          : file(gatsby),
    );
    final openFailed = find.text(english.text('reader.open_failed'));
    await openReader(tester, server, openFailed);
    expect(openFailed, findsOneWidget);

    await runUntil(
      tester,
      firstChapter,
      first: () => tester.tap(
        find.widgetWithText(FilledButton, english.text('reader.retry')),
      ),
    );

    expect(firstChapter, findsOneWidget);
    expect(downloads, 2);
  });

  testWidgets('a refused download says why, with Try again under it', (
    tester,
  ) async {
    final refused = find.text(english.text('errors.internal_error'));
    await openReader(
      tester,
      fileServer(() async => jsonAnswer({'error': 'internal_error'}, 500)),
      refused,
    );

    expect(refused, findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, english.text('reader.retry')),
      findsOneWidget,
    );
  });

  testWidgets('the downloaded file is gone once the reader closes', (
    tester,
  ) async {
    await openReader(
      tester,
      fileServer(() async => file(gatsby)),
      firstChapter,
    );
    List<File> books() => [
      for (final entry in temp.listSync())
        if (entry is File && entry.path.endsWith('.epub')) entry,
    ];
    expect(books(), hasLength(1));

    await runUntil(
      tester,
      find.byType(HomeScreen),
      first: () async {
        await tester.pageBack();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      },
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );

    expect(books(), isEmpty);
  });
}
