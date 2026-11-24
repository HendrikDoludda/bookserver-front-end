import 'dart:io';

import 'package:bookserver/data/epub_book.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/epub_image.dart';
import 'package:bookserver/ui/readers/fixed_layout_page.dart';
import 'package:bookserver/ui/readers/page_turner.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/epubs.dart';
import '../../support/images.dart';
import '../../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });

  late Directory folder;
  setUp(() {
    folder = Directory.systemTemp.createTempSync('bookserver-fixed-');
    PaintingBinding.instance.imageCache.clear();
  });
  tearDown(() => folder.deleteSync(recursive: true));

  /// A fixed-layout book whose pages `OEBPS/p1.xhtml`, `p2.xhtml`… hold [bodies] and link
  /// `OEBPS/style.css`, which holds [css]; its other files are [files].
  EpubBook open(
    List<String> bodies, {
    String css = '',
    Map<String, Object> files = const {},
  }) {
    final ids = [for (var page = 1; page <= bodies.length; page++) 'p$page'];
    final epub = EpubBook.open(
      writeEpub(folder, {
        'META-INF/container.xml': containerXml(),
        'OEBPS/content.opf': packageXml(
          {for (final id in ids) id: '$id.xhtml'},
          ids,
          fixedLayout: true,
        ),
        for (final (index, body) in bodies.indexed)
          'OEBPS/${ids[index]}.xhtml': fixedPageXhtml(body),
        'OEBPS/style.css': css,
        ...files,
      }),
    );
    addTearDown(epub.close);
    return epub;
  }

  final loads = <(String, int)>[];
  setUp(loads.clear);
  Future<void> countLoads(String family, List<Uint8List> files) async =>
      loads.add((family, files.length));

  /// The pages the turner said it landed on, in order.
  final turns = <int>[];
  var taps = 0;
  setUp(() {
    turns.clear();
    taps = 0;
  });

  /// Shows [book]'s pages in a page turner, as the EPUB reader does.
  Future<void> show(WidgetTester tester, FixedLayoutBook book) async {
    await pumpScreen(
      tester,
      catalog: english,
      screen: Scaffold(
        body: PageTurner(
          count: book.book.chapters.length,
          onPageChanged: turns.add,
          onTap: () => taps++,
          pageBuilder: (context, index, decodeWidth) => FixedLayoutPage(
            key: ValueKey(index),
            book: book,
            index: index,
            decodeWidth: decodeWidth,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder text(String text) => find.text(text, findRichText: true);

  /// Where the page on screen is drawn.
  Rect pageRect(WidgetTester tester) => tester.getRect(
    find.descendant(
      of: find.byType(FixedLayoutPage),
      matching: find.byType(Stack),
    ),
  );

  /// Taps the middle of [part] in the line [line]. `tapOnText` can't: it leaves out the scale
  /// of the page the text is drawn on.
  Future<void> tapOn(WidgetTester tester, String line, String part) async {
    final paragraph = tester.renderObject<RenderParagraph>(text(line));
    final start = line.indexOf(part);
    final box = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: start + part.length),
        )
        .first
        .toRect();
    await tester.tapAt(paragraph.localToGlobal(box.center));
  }

  void turnTo(WidgetTester tester, int index) =>
      tester.state<PageTurnerState>(find.byType(PageTurner)).turnTo(index);

  testWidgets(
    'draws each line where the book puts it, the page scaled to fit',
    (tester) async {
      await show(
        tester,
        FixedLayoutBook(
          open([
            '<div style="left:100px;top:200px">first</div>'
                '<div style="left:500px;top:1000px">second</div>',
          ]),
          7,
          loadFont: countLoads,
        ),
      );

      final page = pageRect(tester);
      expect(page.height / page.width, moreOrLessEquals(1.5));
      expect(
        page.height,
        lessThanOrEqualTo(600),
        reason: 'the window is 600 high',
      );
      final scale = page.width / 1000;
      expect(
        tester.getTopLeft(text('first')),
        offsetMoreOrLessEquals(page.topLeft + const Offset(100, 200) * scale),
      );
      expect(
        tester.getTopLeft(text('second')),
        offsetMoreOrLessEquals(page.topLeft + const Offset(500, 1000) * scale),
      );
    },
  );

  testWidgets("a run's font, size, colour and line height; a line's strut", (
    tester,
  ) async {
    await show(
      tester,
      FixedLayoutBook(
        open(
          [
            '<div class="a" style="left:0;top:0">big <span class="b">small</span></div>',
          ],
          css: '''
@font-face { font-family: "Gotham Book"; src: url(fonts/gotham.otf); }
div.a { font-family: "Gotham Book"; font-size: 20px; line-height: 30px; color: #123456;
  font-weight: bold; font-style: italic; letter-spacing: 2px; }
span.b { font-family: Helvetica; font-size: 10px; text-decoration: underline; }''',
          files: {
            'OEBPS/fonts/gotham.otf': [1, 2, 3],
          },
        ),
        7,
        loadFont: countLoads,
      ),
    );

    final rich = tester.widget<RichText>(text('big small'));
    expect(rich.softWrap, isFalse);
    expect(rich.textScaler, TextScaler.noScaling);
    expect(rich.strutStyle!.fontFamily, 'book7-Gotham Book');
    expect(rich.strutStyle!.fontSize, 20);
    expect(rich.strutStyle!.height, 1.5);
    final line = (rich.text as TextSpan).children!.single as TextSpan;
    final [big, small] = [
      for (final run in line.children!) (run as TextSpan).style!,
    ];
    expect(
      big.fontFamily,
      'book7-Gotham Book',
      reason: 'a family the book brings, under its own name',
    );
    expect(big.fontSize, 20);
    expect(big.height, 1.5);
    expect(big.leadingDistribution, TextLeadingDistribution.even);
    expect(big.color, const Color(0xFF123456));
    expect(big.fontWeight, FontWeight.w700);
    expect(big.fontStyle, FontStyle.italic);
    expect(big.letterSpacing, 2);
    expect(big.decoration, TextDecoration.none);
    expect(small.fontFamily, 'Helvetica', reason: 'a family it does not bring');
    expect(small.fontSize, 10);
    expect(small.height, 3, reason: 'the line height of 30 px it inherits');
    expect(small.decoration, TextDecoration.underline);
    expect(loads, [('book7-Gotham Book', 1)]);
  });

  testWidgets('a line placed by its bottom keeps its bottom edge there', (
    tester,
  ) async {
    await show(
      tester,
      FixedLayoutBook(
        open([
          '<div style="left:100px;bottom:100px;font-size:40px;line-height:60px">low</div>',
        ]),
        7,
        loadFont: countLoads,
      ),
    );

    final page = pageRect(tester);
    final scale = page.width / 1000;
    expect(
      tester.getBottomLeft(text('low')),
      offsetMoreOrLessEquals(page.topLeft + const Offset(100, 1400) * scale),
    );
    expect(
      tester.getBottomLeft(text('low')).dy - tester.getTopLeft(text('low')).dy,
      moreOrLessEquals(60 * scale),
      reason: 'its top follows from its height',
    );
  });

  testWidgets('a rotated line turns around its top left', (tester) async {
    await show(
      tester,
      FixedLayoutBook(
        open(
          ['<div class="side" style="left:900px;top:400px">47 Breakfast</div>'],
          css:
              'div.side { transform: rotate(90deg); transform-origin: 0% 0%; }',
        ),
        7,
        loadFont: countLoads,
      ),
    );

    final page = pageRect(tester);
    final scale = page.width / 1000;
    final line = tester.renderObject<RenderBox>(text('47 Breakfast'));
    final corner = line.localToGlobal(Offset.zero);
    expect(
      corner,
      offsetMoreOrLessEquals(page.topLeft + const Offset(900, 400) * scale),
    );
    expect(
      line.localToGlobal(const Offset(10, 0)) - corner,
      offsetMoreOrLessEquals(Offset(0, 10 * scale)),
      reason: 'the text runs downwards',
    );
  });

  testWidgets('a line set large and scaled down keeps its origin in place', (
    tester,
  ) async {
    await show(
      tester,
      FixedLayoutBook(
        open(
          ['<div class="t" style="left:100px;bottom:100px">small print</div>'],
          css:
              '.t { font-size: 40px; line-height: 60px; transform: scale(0.25); '
              'transform-origin: bottom left; }',
        ),
        7,
        loadFont: countLoads,
      ),
    );

    final page = pageRect(tester);
    final scale = page.width / 1000;
    final line = text('small print');
    final unscaled = tester.getSize(line);
    expect(
      tester.getBottomLeft(line),
      offsetMoreOrLessEquals(page.topLeft + const Offset(100, 1400) * scale),
    );
    expect(
      tester.getTopRight(line),
      offsetMoreOrLessEquals(
        tester.getBottomLeft(line) +
            Offset(unscaled.width, -unscaled.height) * 0.25 * scale,
      ),
      reason: 'a quarter of its size on the page',
    );
  });

  testWidgets(
    "a box's transform places and scales the lines inside it, and their links still turn pages",
    (tester) async {
      await show(
        tester,
        FixedLayoutBook(
          open(
            [
              '<div class="text"><span class="l" style="left:400px;bottom:2000px">'
                  'small <a href="p2.xhtml">print</a></span></div>',
              '<div style="left:100px;top:100px">two</div>',
            ],
            css:
                '.text { width: 100%; height: 100%; transform: scale(0.25); '
                'transform-origin: left bottom; } '
                '.l { font-size: 40px; line-height: 60px; }',
          ),
          7,
          loadFont: countLoads,
        ),
      );

      final page = pageRect(tester);
      final scale = page.width / 1000;
      final line = text('small print');
      expect(
        tester.getBottomLeft(line),
        offsetMoreOrLessEquals(page.topLeft + const Offset(100, 1000) * scale),
        reason: '2000 px above the box\'s bottom, a quarter of it on the page',
      );
      expect(
        tester.getBottomLeft(line).dy - tester.getTopLeft(line).dy,
        moreOrLessEquals(60 * 0.25 * scale),
      );

      await tapOn(tester, 'small print', 'print');
      await tester.pumpAndSettle();
      expect(turns, [1]);
      expect(text('two'), findsOneWidget);
    },
  );

  testWidgets(
    'pictures are drawn where their boxes place them, below the text',
    (tester) async {
      await show(
        tester,
        FixedLayoutBook(
          open(
            [
              '<div style="left:100px;top:100px">over</div>'
                  '<div style="left:0;bottom:0;width:1000px;height:1500px">'
                  '<img src="images/photo.png" width="1000" height="1500"/></div>'
                  '<div style="width:100%;height:100%;transform:scale(0.5);transform-origin:0 0">'
                  '<img src="images/photo.png" width="1000" height="1500"/></div>',
            ],
            files: {'OEBPS/images/photo.png': onePixelPng},
          ),
          7,
          loadFont: countLoads,
        ),
      );

      final page = pageRect(tester);
      final pictures = find.descendant(
        of: find.byType(FixedLayoutPage),
        matching: find.byType(Image),
      );
      expect(
        tester.getRect(pictures.first),
        rectMoreOrLessEquals(page),
        reason: 'the whole page',
      );
      final half = tester.renderObject<RenderBox>(pictures.last);
      expect(
        Rect.fromPoints(
          half.localToGlobal(Offset.zero),
          half.localToGlobal(half.size.bottomRight(Offset.zero)),
        ),
        rectMoreOrLessEquals(
          Rect.fromLTWH(page.left, page.top, page.width / 2, page.height / 2),
        ),
        reason: 'its box scaled to half, from the top left',
      );
      final stack = tester.widget<Stack>(
        find.descendant(
          of: find.byType(FixedLayoutPage),
          matching: find.byType(Stack),
        ),
      );
      bool holds(Widget child, Finder finder) => find
          .descendant(of: find.byWidget(child), matching: finder)
          .evaluate()
          .isNotEmpty;
      expect(
        [
          for (final child in stack.children.skip(1))
            holds(child, find.byType(Image))
                ? 'picture'
                : holds(child, text('over'))
                ? 'line'
                : 'other',
        ],
        ['picture', 'picture', 'line'],
        reason: 'the pictures, then the line, though the page lists it first',
      );
    },
  );

  testWidgets(
    "a run's margin-left moves it and all after it, back when negative",
    (tester) async {
      await show(
        tester,
        FixedLayoutBook(
          open([
            '<div style="left:100px;top:100px;font-size:20px">a'
                '<span style="margin-left:50px">b</span>'
                '<span style="margin-left:-10px">c</span></div>'
                '<div style="left:100px;top:300px;font-size:20px">x<span>y</span><span>z</span></div>'
                '<div style="left:100px;top:500px;font-size:20px">'
                '<span style="margin-left:30px">q</span>rs</div>',
          ]),
          7,
          loadFont: countLoads,
        ),
      );

      // Where the character at [index] of [line] starts; each margin is a word joiner in the text.
      double start(String line, int index) => tester
          .renderObject<RenderParagraph>(text(line))
          .getBoxesForSelection(
            TextSelection(baseOffset: index, extentOffset: index + 1),
          )
          .first
          .left;
      const spaced = 'a⁠b⁠c';
      expect(
        start(spaced, 0),
        moreOrLessEquals(start('xyz', 0)),
        reason: 'the character before a margin stays',
      );
      expect(start(spaced, 2) - start('xyz', 1), moreOrLessEquals(50));
      expect(
        start(spaced, 4) - start('xyz', 2),
        moreOrLessEquals(40),
        reason: 'both margins',
      );
      expect(
        start('⁠⁠qrs', 2) - start('xyz', 0),
        moreOrLessEquals(30),
        reason: "one before the line's first character",
      );
    },
  );

  testWidgets('a line that names no origin turns around its middle', (
    tester,
  ) async {
    await show(
      tester,
      FixedLayoutBook(
        open([
          '<div style="left:100px;top:200px;transform:rotate(180deg)">upside down</div>',
        ]),
        7,
        loadFont: countLoads,
      ),
    );

    final page = pageRect(tester);
    final scale = page.width / 1000;
    final line = text('upside down');
    final size = tester.getSize(line);
    expect(
      tester.getTopLeft(line),
      offsetMoreOrLessEquals(
        page.topLeft +
            (const Offset(100, 200) + size.bottomRight(Offset.zero)) * scale,
      ),
      reason: 'its top left turns onto where its bottom right was',
    );
  });

  testWidgets(
    'the background: its colour, then its picture, fitted and aligned',
    (tester) async {
      await show(
        tester,
        FixedLayoutBook(
          open(
            ['<div id="page" style="left:0;top:0"></div>', '<div></div>'],
            css:
                '#page { background-color: #F0E0D0; background-image: url(images/photo.png);'
                ' background-size: auto 100%; background-position: center; }',
            files: {'OEBPS/images/photo.png': onePixelPng},
          ),
          7,
          loadFont: countLoads,
        ),
      );
      Color paper() => tester
          .widget<ColoredBox>(
            find.descendant(
              of: find.byType(FixedLayoutPage),
              matching: find.byType(ColoredBox),
            ),
          )
          .color;

      expect(paper(), const Color(0xFFF0E0D0));
      final picture = tester.widget<Image>(
        find.descendant(
          of: find.byType(FixedLayoutPage),
          matching: find.byType(Image),
        ),
      );
      expect(picture.fit, BoxFit.fitHeight);
      expect(picture.alignment, Alignment.center);
      expect(
        picture.image,
        isA<ResizeImage>()
            .having(
              (image) => image.width,
              'width',
              (tester.view.physicalSize.shortestSide * 2).round(),
            )
            .having(
              (image) => image.imageProvider,
              'picture',
              isA<EpubImage>().having(
                (image) => image.path,
                'path',
                'OEBPS/images/photo.png',
              ),
            ),
      );

      turnTo(tester, 1);
      await tester.pumpAndSettle();
      expect(
        paper(),
        const Color(0xFFFFFFFF),
        reason: 'a page without a colour',
      );
      expect(
        find.descendant(
          of: find.byType(FixedLayoutPage),
          matching: find.byType(Image),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'a background drawn at its own size is decoded whole, whatever the decode width',
    (tester) async {
      await show(
        tester,
        FixedLayoutBook(
          open(
            ['<div id="page" style="left:0;top:0"></div>'],
            css:
                '#page { background-image: url(images/photo.png);'
                ' background-size: auto; }',
            files: {'OEBPS/images/photo.png': onePixelPng},
          ),
          7,
          loadFont: countLoads,
        ),
      );

      final picture = tester.widget<Image>(
        find.descendant(
          of: find.byType(FixedLayoutPage),
          matching: find.byType(Image),
        ),
      );
      expect(picture.fit, BoxFit.none);
      expect(
        picture.image,
        isA<EpubImage>().having(
          (image) => image.path,
          'path',
          'OEBPS/images/photo.png',
        ),
      );
    },
  );

  testWidgets(
    'a tap on a link turns to its page; on other text, it is the turner\'s',
    (tester) async {
      // The line in the middle third, where a tap the turner gets is no page turn.
      await show(
        tester,
        FixedLayoutBook(
          open([
            '<div style="left:400px;top:100px">Kale, <a href="p3.xhtml">11</a>, <a href="p2.xhtml">102–3</a></div>',
            '<div style="left:100px;top:100px">two</div>',
            '<div style="left:100px;top:100px">three</div>',
          ]),
          7,
          loadFont: countLoads,
        ),
      );

      const line = 'Kale, 11, 102–3';
      await tapOn(tester, line, 'Kale');
      await tester.pumpAndSettle();
      expect(turns, isEmpty);
      expect(taps, 1, reason: 'plain text leaves the tap to the turner');

      await tapOn(tester, line, '11');
      await tester.pumpAndSettle();
      expect(turns, [2]);
      expect(text('three'), findsOneWidget);
      expect(taps, 1, reason: 'the link took the tap');
    },
  );

  testWidgets('loads the fonts a book brings once, under names of its own', (
    tester,
  ) async {
    final epub = open(
      [
        '<div class="a" style="left:0;top:0">one</div>',
        '<div class="a" style="left:0;top:0">two</div>',
      ],
      css:
          '@font-face { font-family: Gotham; src: url(fonts/gotham.otf); }'
          ' div.a { font-family: Gotham; }',
      files: {
        'OEBPS/fonts/gotham.otf': [1, 2, 3],
      },
    );
    await show(tester, FixedLayoutBook(epub, 8, loadFont: countLoads));
    turnTo(tester, 1);
    await tester.pumpAndSettle();
    expect(text('two'), findsOneWidget);

    final again = FixedLayoutBook(epub, 8, loadFont: countLoads);
    final page = again.prepare(0);
    await tester.pump();
    await page;

    expect(loads, [('book8-Gotham', 1)]);
  });

  testWidgets("a page that can't be read says so; the next one shows", (
    tester,
  ) async {
    await show(
      tester,
      FixedLayoutBook(
        open(['<div>never closed', '<div style="left:0;top:0">two</div>']),
        7,
        loadFont: countLoads,
      ),
    );

    expect(find.text(english.text('reader.page_failed')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(text('two'), findsOneWidget);
  });

  testWidgets('a page is parsed only once a page turn has stopped moving', (
    tester,
  ) async {
    final book = FixedLayoutBook(
      open([
        for (final page in ['one', 'two', 'three'])
          '<div style="left:0;top:0">$page</div>',
      ]),
      7,
      loadFont: countLoads,
    );
    await show(tester, book);
    expect(book.prepared(2), isNull, reason: 'two pages ahead');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(const ValueKey(2), skipOffstage: false),
      findsOneWidget,
      reason: 'the page after next is built while the turn moves',
    );
    // Frames later, the turn still moving: time enough to have parsed it.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester.state<PageTurnerState>(find.byType(PageTurner)).moving.value,
      isTrue,
    );
    expect(book.prepared(2), isNull);

    await tester.pumpAndSettle();
    expect(book.prepared(2), isNotNull);
  });
}
