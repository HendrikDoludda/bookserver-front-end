import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/preferences.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/epub_image.dart';
import 'package:bookserver/ui/home_screen.dart';
import 'package:bookserver/ui/readers/anchored_list.dart';
import 'package:bookserver/ui/readers/open_book.dart';
import 'package:bookserver/ui/readers/page_turner.dart';
import 'package:bookserver/ui/readers/reader_frame.dart';
import 'package:bookserver/ui/readers/zoom.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../support/epubs.dart';
import '../../support/fake_path_provider.dart';
import '../../support/fake_server.dart';
import '../../support/images.dart';
import '../../support/memory_preferences_store.dart';
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

  /// A flowing EPUB of three chapters of 60 numbered paragraphs, each chapter wrapped the way
  /// Gatsby's are and longer than `HtmlWidget` builds in the frame it appears.
  final longBook = epubBytes({
    'META-INF/container.xml': containerXml(),
    'OEBPS/content.opf': packageXml(
      {
        for (var chapter = 1; chapter <= 3; chapter++)
          'c$chapter': 'c$chapter.xhtml',
      },
      ['c1', 'c2', 'c3'],
    ),
    for (var chapter = 1; chapter <= 3; chapter++)
      'OEBPS/c$chapter.xhtml': chapterXhtml(
        '<section class="chapter" title="Chapter $chapter">'
        '<div class="titlepage"><div><h1>Chapter $chapter</h1></div></div>'
        '${[for (var paragraph = 1; paragraph <= 60; paragraph++) '<p>Chapter $chapter, paragraph $paragraph: ${'words ' * 30}</p>'].join()}'
        '</section>',
      ),
  });

  /// A flowing EPUB whose first 30 blocks are a short line each and whose next 30 are long.
  final unevenBook = epubBytes({
    'META-INF/container.xml': containerXml(),
    'OEBPS/content.opf': packageXml({'one': 'one.xhtml'}, ['one']),
    'OEBPS/one.xhtml': chapterXhtml(
      [
        for (var block = 1; block <= 30; block++) '<p>Short $block</p>',
        for (var block = 1; block <= 30; block++)
          '<p>Long $block: ${'words ' * 100}</p>',
      ].join(),
    ),
  });

  /// A fixed-layout EPUB of two pages.
  final fixedBook = epubBytes({
    'META-INF/container.xml': containerXml(),
    'OEBPS/content.opf': packageXml(
      {'p1': 'p1.xhtml', 'p2': 'p2.xhtml'},
      ['p1', 'p2'],
      fixedLayout: true,
    ),
    'OEBPS/p1.xhtml': fixedPageXhtml(
      '<div style="left:100px;top:100px">The first page</div>',
    ),
    'OEBPS/p2.xhtml': fixedPageXhtml(
      '<div style="left:100px;top:100px">The second page</div>',
    ),
  });

  /// A flowing EPUB with contents: two chapters of 40 paragraphs, the first ending in a link to
  /// the second's note, the second in a link out of the book; and an entry for a file outside the
  /// reading order. Its blocks: chapter one's heading 0, its link 41; chapter two's heading 42, the
  /// note 83, the link out 84.
  final contentsBook = epubBytes({
    'META-INF/container.xml': containerXml(),
    'OEBPS/content.opf': packageXml(
      {
        'nav': 'nav.xhtml',
        'c1': 'c1.xhtml',
        'c2': 'c2.xhtml',
        'extra': 'extra.xhtml',
      },
      ['c1', 'c2', 'extra'],
      properties: {'nav': 'nav'},
    ).replaceFirst('idref="extra"', 'idref="extra" linear="no"'),
    'OEBPS/nav.xhtml': navXhtml(
      '<ol><li><a href="c1.xhtml">Chapter One</a></li>'
      '<li><a href="c2.xhtml">Chapter Two</a>'
      '<ol><li><a href="c2.xhtml#note">The note</a></li></ol></li>'
      '<li><a href="extra.xhtml">Extra</a></li></ol>',
    ),
    'OEBPS/c1.xhtml': chapterXhtml(
      '<h1>Chapter One</h1>'
      '${[for (var paragraph = 1; paragraph <= 40; paragraph++) '<p>One, paragraph $paragraph: ${'words ' * 20}</p>'].join()}'
      '<p><a href="c2.xhtml#note">See the note</a></p>',
    ),
    'OEBPS/c2.xhtml': chapterXhtml(
      '<h1>Chapter Two</h1>'
      '${[for (var paragraph = 1; paragraph <= 40; paragraph++) '<p>Two, paragraph $paragraph: ${'words ' * 20}</p>'].join()}'
      '<p id="note">The note itself</p>'
      '<p><a href="https://example.com/away">Out of the book</a></p>',
    ),
    'OEBPS/extra.xhtml': chapterXhtml('<p>Extra</p>'),
  });

  /// A fixed-layout EPUB of two pages with contents.
  final fixedContentsBook = epubBytes({
    'META-INF/container.xml': containerXml(),
    'OEBPS/content.opf': packageXml(
      {'nav': 'nav.xhtml', 'p1': 'p1.xhtml', 'p2': 'p2.xhtml'},
      ['p1', 'p2'],
      fixedLayout: true,
      properties: {'nav': 'nav'},
    ),
    'OEBPS/nav.xhtml': navXhtml(
      '<ol><li><a href="p1.xhtml">First</a></li>'
      '<li><a href="p2.xhtml">Second</a></li></ol>',
    ),
    'OEBPS/p1.xhtml': fixedPageXhtml(
      '<div style="left:100px;top:100px">The first page</div>',
    ),
    'OEBPS/p2.xhtml': fixedPageXhtml(
      '<div style="left:100px;top:100px">The second page</div>',
    ),
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

  /// Starts the app signed in, with the device's [preferences], and opens the book the way a tap on
  /// its card does, until [shown].
  Future<void> openReader(
    WidgetTester tester,
    FakeServer server,
    Finder shown, {
    PreferencesController? preferences,
  }) async {
    final session = await pumpApp(
      tester,
      catalog: english,
      store: signedInStore(),
      server: server,
      preferences: preferences,
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

  testWidgets(
    'a tap on the text shows and hides the bar; a link keeps its tap',
    (tester) async {
      await openReader(
        tester,
        fileServer(() async => file(gatsby)),
        firstChapter,
      );
      final frame = tester.state<ReaderFrameState>(find.byType(ReaderFrame));
      expect(frame.barShown, isTrue);

      await tester.tap(firstChapter);
      await tester.pump();
      expect(frame.barShown, isFalse);

      // On the link's first letters: a tap beside the text of a line hits no link.
      final link = find.textContaining('On to chapter two', findRichText: true);
      await tester.tapAt(tester.getTopLeft(link) + const Offset(8, 8));
      await tester.pump();
      expect(frame.barShown, isFalse, reason: 'the link took the tap');
      expect(
        tester.state<AnchoredListState>(find.byType(AnchoredList)).topItem,
        3,
        reason: "chapter two's heading, where the link goes",
      );

      await tester.tap(find.text('Chapter two', findRichText: true));
      await tester.pump();
      expect(frame.barShown, isTrue);
    },
  );

  testWidgets('scrolling the text hides the bar', (tester) async {
    await openReader(
      tester,
      fileServer(() async => file(longBook)),
      find.textContaining('Chapter 1, paragraph 1:', findRichText: true),
    );
    final frame = tester.state<ReaderFrameState>(find.byType(ReaderFrame));

    await tester.drag(find.byType(Scrollable).last, const Offset(0, -200));
    await tester.pump();

    expect(frame.barShown, isFalse);
  });

  testWidgets(
    'scrolling back up moves the text exactly as far as the list scrolls',
    (tester) async {
      await openReader(
        tester,
        fileServer(() async => file(longBook)),
        find.textContaining('Chapter 1, paragraph 1:', findRichText: true),
      );
      final list = find.byType(Scrollable).last;
      final position = tester.state<ScrollableState>(list).position;
      Finder paragraph(String label) =>
          find.textContaining('$label:', findRichText: true);

      /// The label of a paragraph whose top is in the upper half of the list.
      String labelOnScreen() {
        final screen = tester.getRect(list);
        for (final element
            in find
                .textContaining(', paragraph ', findRichText: true)
                .evaluate()) {
          final top = (element.renderObject! as RenderBox)
              .localToGlobal(Offset.zero)
              .dy;
          if (top > screen.top && top < screen.center.dy) {
            return (element.widget as RichText).text
                .toPlainText()
                .split(':')
                .first;
          }
        }
        throw StateError('No paragraph in the upper half of the list.');
      }

      /// Whether the paragraph [label] starts on screen; a whole chapter built as one widget holds
      /// all its paragraphs, on screen or not.
      bool onScreen(String label) {
        if (paragraph(label).evaluate().isEmpty) {
          return false;
        }
        final top = tester.getTopLeft(paragraph(label)).dy;
        final screen = tester.getRect(list);
        return top >= screen.top && top < screen.bottom;
      }

      /// Lets work that only finishes in real time — `HtmlWidget` parses a long text in another
      /// isolate — catch up.
      Future<void> settle() => tester.runAsync(() async {
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      for (
        var step = 0;
        step < 200 && !onScreen('Chapter 3, paragraph 40');
        step++
      ) {
        position.jumpTo(position.pixels + 600);
        await settle();
      }
      expect(onScreen('Chapter 3, paragraph 40'), isTrue);

      // Back up until chapter 2, long gone from the list, is built again and on screen.
      for (
        var step = 0;
        step < 200 && !onScreen('Chapter 2, paragraph 59');
        step++
      ) {
        final label = labelOnScreen();
        final before = tester.getTopLeft(paragraph(label)).dy;
        position.jumpTo(position.pixels - 150);
        await settle();
        expect(
          paragraph(label),
          findsOneWidget,
          reason: '$label, scrolling up 150 from step $step',
        );
        expect(
          tester.getTopLeft(paragraph(label)).dy,
          moreOrLessEquals(before + 150, epsilon: 0.5),
          reason: '$label, scrolling up 150 from step $step',
        );
      }
      expect(onScreen('Chapter 2, paragraph 59'), isTrue);
    },
  );

  testWidgets('each paragraph is an item of its own', (tester) async {
    final first = find.textContaining(
      'Chapter 1, paragraph 1:',
      findRichText: true,
    );
    await openReader(tester, fileServer(() async => file(longBook)), first);

    final item = tester.widget<HtmlWidget>(
      find.ancestor(of: first, matching: find.byType(HtmlWidget)),
    );
    expect(item.html, contains('Chapter 1, paragraph 1:'));
    expect(item.html, isNot(contains('paragraph 2:')));
    expect(item.buildAsync, isFalse);
  });

  testWidgets('paragraphs are 1 em apart, a new chapter further', (
    tester,
  ) async {
    await openReader(
      tester,
      fileServer(() async => file(longBook)),
      find.textContaining('Chapter 1, paragraph 1:', findRichText: true),
    );
    final em = Theme.of(tester.element(find.byType(Scrollable).last))
        .textTheme
        .bodyLarge!
        .fontSize!;
    Rect rectOf(Finder finder) => tester.getRect(finder);
    Finder paragraph(String label) =>
        find.textContaining('$label:', findRichText: true);

    expect(
      rectOf(paragraph('Chapter 1, paragraph 2')).top -
          rectOf(paragraph('Chapter 1, paragraph 1')).bottom,
      em,
    );

    final heading = find.text('Chapter 2', findRichText: true);
    await tester.scrollUntilVisible(
      heading,
      500,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      rectOf(heading).top - rectOf(paragraph('Chapter 1, paragraph 60')).bottom,
      Spacing.large * 2,
    );
  });

  testWidgets("the book's length stays put while scrolling through it", (
    tester,
  ) async {
    await openReader(
      tester,
      fileServer(() async => file(unevenBook)),
      find.textContaining('Short 1', findRichText: true),
    );
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position;

    final lengths = <double>[];
    for (var step = 0; step < 500; step++) {
      lengths.add(position.maxScrollExtent);
      if (position.pixels >= position.maxScrollExtent) {
        break;
      }
      position.jumpTo(
        math.min(position.pixels + 300, position.maxScrollExtent),
      );
      await tester.pump();
    }

    final length = lengths.last;
    for (final (step, guess) in lengths.indexed) {
      expect(
        guess,
        moreOrLessEquals(length, epsilon: length * 0.05),
        reason: 'the length guessed at step $step of ${lengths.length}',
      );
    }
  });

  testWidgets('a fixed-layout book opens page by page in the page turner', (
    tester,
  ) async {
    await openReader(
      tester,
      fileServer(() async => file(fixedBook)),
      find.text('The first page', findRichText: true),
    );

    expect(find.byType(PageTurner), findsOneWidget);
    expect(
      find.text(english.text('reader.page_of', {'page': 1, 'count': 2})),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('The second page', findRichText: true), findsOneWidget);
    expect(
      find.text(english.text('reader.page_of', {'page': 2, 'count': 2})),
      findsOneWidget,
    );
  });

  testWidgets(
    'a fixed-layout book whose spine runs right to left turns its pages that way',
    (tester) async {
      final rightToLeftBook = epubBytes({
        'META-INF/container.xml': containerXml(),
        'OEBPS/content.opf': packageXml(
          {'p1': 'p1.xhtml', 'p2': 'p2.xhtml'},
          ['p1', 'p2'],
          fixedLayout: true,
          pageProgression: 'rtl',
        ),
        'OEBPS/p1.xhtml': fixedPageXhtml(
          '<div style="left:100px;top:100px">The first page</div>',
        ),
        'OEBPS/p2.xhtml': fixedPageXhtml(
          '<div style="left:100px;top:100px">The second page</div>',
        ),
      });
      await openReader(
        tester,
        fileServer(() async => file(rightToLeftBook)),
        find.text('The first page', findRichText: true),
      );

      expect(
        tester.widget<PageTurner>(find.byType(PageTurner)).rightToLeft,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('The second page', findRichText: true), findsOneWidget);
    },
  );

  testWidgets("a fixed-layout book's pages zoom by the steps in the bar", (
    tester,
  ) async {
    await openReader(
      tester,
      fileServer(() async => file(fixedBook)),
      find.text('The first page', findRichText: true),
    );

    await tester.tap(find.byTooltip(english.text('reader.zoom')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text(english.text('reader.zoom_fit_width')),
        matching: find.byWidgetPredicate(
          (widget) => widget is CheckedPopupMenuItem<ZoomStep>,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Its pages are 1000 × 1500, as their viewport says.
    expect(
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value,
      zoomOf(ZoomStep.fitWidth, 2 / 3, tester.getSize(find.byType(PageTurner))),
    );
  });

  testWidgets('a flowing book has no zoom', (tester) async {
    await openReader(
      tester,
      fileServer(() async => file(gatsby)),
      firstChapter,
    );

    expect(find.byTooltip(english.text('reader.zoom')), findsNothing);
  });

  /// The size the flowing text is set in.
  double textSize(WidgetTester tester) => tester
      .widget<HtmlWidget>(find.byType(HtmlWidget).first)
      .textStyle!
      .fontSize!;

  /// The normal size of the reader's text: its size at 100 %.
  double normalSize(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(HtmlWidget).first))
          .textTheme
          .bodyLarge!
          .fontSize!;

  IconButton fontButton(WidgetTester tester, IconData icon) =>
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));

  Future<void> tapFont(WidgetTester tester, String key) async {
    await tester.tap(find.byTooltip(english.text(key)));
    await tester.pump();
  }

  String percent(int value) =>
      english.text('reader.percent', {'percent': value});

  testWidgets("a flowing book's text grows and shrinks by 10 % a tap, from 80 to 200 %, the buttons off at "
      'either end', (tester) async {
    await openReader(
      tester,
      fileServer(() async => file(gatsby)),
      firstChapter,
    );
    final normal = normalSize(tester);
    expect(find.text(percent(100)), findsOneWidget);
    expect(textSize(tester), normal);

    await tapFont(tester, 'reader.font_larger');
    expect(find.text(percent(110)), findsOneWidget);
    expect(textSize(tester), moreOrLessEquals(normal * 1.1));

    for (var tap = 0; tap < 9; tap++) {
      await tapFont(tester, 'reader.font_larger');
    }
    expect(find.text(percent(200)), findsOneWidget);
    expect(textSize(tester), moreOrLessEquals(normal * 2));
    expect(fontButton(tester, Icons.text_increase).onPressed, isNull);

    for (var tap = 0; tap < 12; tap++) {
      await tapFont(tester, 'reader.font_smaller');
    }
    expect(find.text(percent(80)), findsOneWidget);
    expect(textSize(tester), moreOrLessEquals(normal * 0.8));
    expect(fontButton(tester, Icons.text_decrease).onPressed, isNull);
    expect(fontButton(tester, Icons.text_increase).onPressed, isNotNull);
  });

  testWidgets('the block at the top stays there as the text changes size', (
    tester,
  ) async {
    await openReader(
      tester,
      fileServer(() async => file(longBook)),
      find.textContaining('Chapter 1, paragraph 1:', findRichText: true),
    );
    tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position
        .jumpTo(3000);
    await tester.pump();
    AnchoredListState list() =>
        tester.state<AnchoredListState>(find.byType(AnchoredList));
    final top = list().topItem;
    expect(top, greaterThan(10), reason: 'well into the book');
    // The scroll hid the bar.
    tester.state<ReaderFrameState>(find.byType(ReaderFrame)).toggleBar();
    await tester.pumpAndSettle();

    for (final key in [
      'reader.font_larger',
      'reader.font_larger',
      'reader.font_smaller',
    ]) {
      await tapFont(tester, key);
      expect(list().topItem, top, reason: key);
    }
  });

  testWidgets(
    'the text size is kept on the device: the next start of the app opens a book at it',
    (tester) async {
      final kept = MemoryPreferencesStore();
      await openReader(
        tester,
        fileServer(() async => file(gatsby)),
        firstChapter,
        preferences: PreferencesController(store: kept),
      );
      await tapFont(tester, 'reader.font_larger');
      expect(kept.preferences?.fontPercent, 110);

      // A new start of the app, from nothing on screen.
      await tester.pumpWidget(const SizedBox());
      final nextStart = PreferencesController(store: kept);
      await nextStart.load();
      await openReader(
        tester,
        fileServer(() async => file(gatsby)),
        firstChapter,
        preferences: nextStart,
      );

      expect(find.text(percent(110)), findsOneWidget);
      expect(textSize(tester), moreOrLessEquals(normalSize(tester) * 1.1));
    },
  );

  /// Opens the contents in the bar and chooses the entry called [title].
  Future<void> chooseInContents(WidgetTester tester, String title) async {
    await tester.tap(find.byTooltip(english.text('reader.contents')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, title));
    await tester.pumpAndSettle();
  }

  AnchoredListState blockList(WidgetTester tester) =>
      tester.state<AnchoredListState>(find.byType(AnchoredList));

  testWidgets(
    "a flowing book's contents go to a chapter's start, or to the place an entry's anchor names, "
    'at the top; an entry outside the reading order goes nowhere',
    (tester) async {
      await openReader(
        tester,
        fileServer(() async => file(contentsBook)),
        find.text('Chapter One', findRichText: true),
      );

      await chooseInContents(tester, 'The note');
      expect(blockList(tester).topItem, 83);
      expect(find.text('The note itself', findRichText: true), findsOneWidget);

      await chooseInContents(tester, 'Chapter Two');
      expect(blockList(tester).topItem, 42);

      await chooseInContents(tester, 'Extra');
      expect(
        find.widgetWithText(ListTile, 'Extra'),
        findsOneWidget,
        reason: 'the contents stay open',
      );
      expect(blockList(tester).topItem, 42);
    },
  );

  testWidgets('a book without contents has no contents button', (tester) async {
    await openReader(
      tester,
      fileServer(() async => file(gatsby)),
      firstChapter,
    );

    expect(find.byTooltip(english.text('reader.contents')), findsNothing);
  });

  testWidgets(
    "a link in a flowing book's text goes to its place; one out of the book does nothing",
    (tester) async {
      await openReader(
        tester,
        fileServer(() async => file(contentsBook)),
        find.text('Chapter One', findRichText: true),
      );
      blockList(tester).showItem(41);
      await tester.pump();
      final frame = tester.state<ReaderFrameState>(find.byType(ReaderFrame));
      final barShown = frame.barShown;

      // On the link's first letters: a tap beside the text of a line hits no link.
      final toNote = find.textContaining('See the note', findRichText: true);
      await tester.tapAt(tester.getTopLeft(toNote) + const Offset(8, 8));
      await tester.pump();
      expect(blockList(tester).topItem, 83);
      expect(frame.barShown, barShown, reason: 'the link took the tap');

      final away = find.textContaining('Out of the book', findRichText: true);
      await tester.tapAt(tester.getTopLeft(away) + const Offset(8, 8));
      await tester.pump();
      expect(blockList(tester).topItem, 83);
      expect(frame.barShown, barShown, reason: 'the link took the tap');
    },
  );

  testWidgets(
    "a fixed-layout book's contents turn to the page an entry's file makes",
    (tester) async {
      await openReader(
        tester,
        fileServer(() async => file(fixedContentsBook)),
        find.text('The first page', findRichText: true),
      );

      await chooseInContents(tester, 'Second');

      expect(find.text('The second page', findRichText: true), findsOneWidget);
      expect(
        find.text(english.text('reader.page_of', {'page': 2, 'count': 2})),
        findsOneWidget,
      );
    },
  );

  testWidgets('a fixed-layout book has no text size: its pages keep theirs', (
    tester,
  ) async {
    await openReader(
      tester,
      fileServer(() async => file(fixedBook)),
      find.text('The first page', findRichText: true),
    );

    expect(find.byTooltip(english.text('reader.font_larger')), findsNothing);
  });

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
