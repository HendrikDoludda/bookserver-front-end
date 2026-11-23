import 'dart:io';
import 'dart:math' as math;

import 'package:bookserver/data/epub_book.dart';
import 'package:bookserver/data/epub_layout.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/epubs.dart';

void main() {
  late Directory folder;
  setUp(
    () => folder = Directory.systemTemp.createTempSync('bookserver-layout-'),
  );
  tearDown(() => folder.deleteSync(recursive: true));

  /// Opens a fixed-layout book of [pages] (path under `OEBPS/` → page, in reading order) and
  /// [files] (path → content). One book per test: each is written to the same file.
  BookStyles open(
    Map<String, String> pages, [
    Map<String, Object> files = const {},
  ]) {
    final ids = [for (var index = 0; index < pages.length; index++) 'p$index'];
    final epub = EpubBook.open(
      writeEpub(folder, {
        'META-INF/container.xml': containerXml(),
        'OEBPS/content.opf': packageXml(
          {for (final (index, path) in pages.keys.indexed) ids[index]: path},
          ids,
          fixedLayout: true,
        ),
        for (final MapEntry(key: path, value: page) in pages.entries)
          'OEBPS/$path': page,
        ...files,
      }),
    );
    addTearDown(epub.close);
    return BookStyles(epub);
  }

  /// The one page of a book whose page holds [body] and links `OEBPS/style.css`, holding [css].
  FixedPage page(String body, {String css = ''}) => FixedPage.parse(
    open({'page.xhtml': fixedPageXhtml(body)}, {'OEBPS/style.css': css}),
    0,
  );

  List<String> texts(TextLine line) => [for (final run in line.runs) run.text];

  RunStyle styleOf(FixedPage page) => page.lines.single.runs.single.style;

  /// A transform whose `a`–`f` are [expected], each within rounding.
  Matcher isTransform(List<double> expected) => isA<LineTransform>().having(
    (transform) => [
      transform.a,
      transform.b,
      transform.c,
      transform.d,
      transform.e,
      transform.f,
    ],
    'a–f',
    [for (final value in expected) closeTo(value, 1e-12)],
  );

  test(
    'rules apply by specificity, then in order, the style attribute last',
    () {
      final fixed = page(
        '''
<div class="big" id="first" style="left:0;top:0">first</div>
<div class="big" style="left:0;top:10px">second</div>
<div class="big" style="left:0;top:20px;font-size:12px">third</div>''',
        css: '''
#first { color: #0000ff; }
div.big { color: #00ff00; font-size: 20px; }
.big { color: #ff0000; font-size: 30px; }
div { color: #111111; font-size: 10px; letter-spacing: 1px; }
div { letter-spacing: 2px; }''',
      );

      final [first, second, third] = [
        for (final line in fixed.lines) line.runs.single.style,
      ];
      expect(
        first.color,
        const Color(0xFF0000FF),
        reason: 'an id outweighs classes, though its rule comes first',
      );
      expect(
        first.fontSize,
        20,
        reason: 'div.big outweighs .big, though .big comes later',
      );
      expect(first.letterSpacing, 2, reason: 'of two equal rules, the later');
      expect(second.color, const Color(0xFF00FF00));
      expect(third.fontSize, 12, reason: 'the style attribute outweighs rules');
    },
  );

  test('of equal rules in two stylesheets, the one linked later wins', () {
    final styles = open(
      {
        'one.xhtml': fixedPageXhtml(
          '<div class="x" style="left:0;top:0">one</div>',
          stylesheets: ['red.css', 'green.css'],
        ),
        'two.xhtml': fixedPageXhtml(
          '<div class="x" style="left:0;top:0">two</div>',
          stylesheets: ['green.css', 'red.css'],
        ),
      },
      {
        'OEBPS/red.css': '.x { color: #ff0000; }',
        'OEBPS/green.css': '.x { color: #00ff00; }',
      },
    );

    expect(styleOf(FixedPage.parse(styles, 0)).color, const Color(0xFF00FF00));
    expect(styleOf(FixedPage.parse(styles, 1)).color, const Color(0xFFFF0000));
  });

  test('text styles pass to the elements inside a line', () {
    final line = page(
      '<div class="line" style="left:0;top:0">plain <span class="big">big</span> <span>same</span></div>',
      css: '''
div.line { font-family: "Merriam Sans", serif; font-size: 20px; line-height: 150%;
  color: #123456; font-weight: bold; font-style: italic; letter-spacing: 0.1em;
  text-decoration: underline; }
span.big { font-size: 2em; color: #fff; }''',
    ).lines.single;

    expect(texts(line), ['plain ', 'big', ' ', 'same']);
    expect(line.style.fontSize, 20, reason: "the line's own style");
    expect(line.style.lineHeight, 30);
    final [plain, big, space, same] = [for (final run in line.runs) run.style];
    expect(plain.fontFamily, 'Merriam Sans');
    expect(plain.fontSize, 20);
    expect(plain.lineHeight, 30);
    expect(plain.color, const Color(0xFF123456));
    expect(plain.fontWeight, FontWeight.w700);
    expect(plain.italic, isTrue);
    expect(plain.letterSpacing, 2);
    expect(plain.underline, isTrue);

    expect(big.fontFamily, 'Merriam Sans');
    expect(big.fontSize, 40);
    expect(big.color, const Color(0xFFFFFFFF));
    expect(
      big.lineHeight,
      30,
      reason:
          'a % line height is worked out where it is declared, then passed on',
    );
    expect(big.letterSpacing, 2, reason: 'and so is a letter spacing in em');
    expect(big.italic, isTrue);
    expect(big.underline, isTrue);

    for (final style in [space, same]) {
      expect(style.fontSize, 20);
      expect(style.color, const Color(0xFF123456));
    }
  });

  test(
    'reads lengths in px, % and em, and colours as #rgb, #rrggbb and rgb()',
    () {
      final fixed = page('''
<div style="left:10%;top:2em;font-size:20px">relative</div>
<div style="left:0;top:0;color:#abc">short</div>
<div style="left:0;top:0;color:rgb(1, 2, 300)">commas</div>
<div style="left:0;top:0;color:rgb(10 20 30)">spaces</div>
<div style="left:0;top:0">plain</div>''');

      final [relative, short, commas, spaces, plain] = fixed.lines;
      expect(relative.position, const Offset(100, 40));
      expect(short.runs.single.style.color, const Color(0xFFAABBCC));
      expect(commas.runs.single.style.color, const Color(0xFF0102FF));
      expect(spaces.runs.single.style.color, const Color(0xFF0A141E));

      final initial = plain.runs.single.style;
      expect(initial.fontFamily, isNull);
      expect(initial.fontSize, 16);
      expect(initial.fontWeight, FontWeight.w400);
      expect(initial.italic, isFalse);
      expect(initial.lineHeight, isNull);
      expect(initial.color, const Color(0xFF000000));
      expect(initial.letterSpacing, 0);
      expect(initial.underline, isFalse);
    },
  );

  test('a value it cannot read is dropped, and the one before it applies', () {
    final line = page(
      '<div class="x" style="left:5px;left:5vw;top:0">text</div>',
      css:
          '.x { color: #333333; color: rebeccapurple; font-size: 18px; font-size: 12pt;'
          ' font-weight: 600; font-weight: bolder; line-height: 20px; line-height: 1.5; }',
    ).lines.single;

    expect(line.position, const Offset(5, 0));
    final style = line.runs.single.style;
    expect(style.color, const Color(0xFF333333));
    expect(style.fontSize, 18);
    expect(style.fontWeight, const FontWeight(600));
    expect(style.lineHeight, 20);
  });

  test('inherit takes the outer value, and normal resets a line height', () {
    final line = page(
      '<div class="x" style="left:0;top:0"><a class="y">a</a><span class="n">n</span></div>',
      css:
          '.x { color: #00ff00; line-height: 30px; } a { color: #ff0000; }'
          ' a.y { color: inherit; } span.n { line-height: normal; }',
    ).lines.single;

    final [a, n] = [for (final run in line.runs) run.style];
    expect(a.color, const Color(0xFF00FF00));
    expect(a.lineHeight, 30);
    expect(n.lineHeight, isNull);
  });

  test('rules it cannot apply are left out without errors', () {
    final line = page(
      '<div id="page" style="left:0;top:0"><div class="cls_1 para" style="left:0;top:0">text <span>more</span></div></div>',
      css: '''
div.para { word-spacing: 4px; display: inline-block; color: #00ff00; }
div.para[class^=cls] { color: #ff0000; }
div.para:after { color: #ff0000; }
#page div.para { color: #ff0000; }
div.para > span { color: #ff0000; }
psan.para { color: #ff0000; }
@media print { div.para { color: #ff0000; } }
.missing > p, div.para { font-size: 30px; }
* { letter-spacing: 3px; }''',
    ).lines.single;

    expect(texts(line), ['text ', 'more']);
    for (final run in line.runs) {
      expect(run.style.color, const Color(0xFF00FF00), reason: run.text);
      expect(run.style.fontSize, 30, reason: run.text);
      expect(run.style.letterSpacing, 3, reason: run.text);
    }
  });

  test('a value it cannot parse costs only its declaration, not the rest of the stylesheet', () {
    final fixed = page(
      '<div id="page"></div><div class="x" style="left:0;top:0">x</div>',
      css: '''
#page { background-image: url(a.png); background-size:auto100%; background-position: center; }
div.x { color: #00ff00; }''',
    );

    expect(fixed.background.image, 'OEBPS/a.png');
    expect(fixed.background.fit, BoxFit.none);
    expect(
      fixed.background.alignment,
      Alignment.center,
      reason: 'the declaration after it',
    );
    expect(
      styleOf(fixed).color,
      const Color(0xFF00FF00),
      reason: 'the rule after it',
    );
  });

  test(
    'a style attribute keeps the declarations around one it cannot parse',
    () {
      final line = page(
        '<div style="left:5px;background-size:auto100%;top:7px;color:#00ff00">t</div>',
      ).lines.single;

      expect(line.position, const Offset(5, 7));
      expect(line.runs.single.style.color, const Color(0xFF00FF00));
    },
  );

  test('strings, brackets and comments split nothing; a } in a string closes nothing', () {
    final fixed = page(
      '''
<div id="page"></div>
<div class="x" style="left:0;top:0">x</div>
<div class="y" style="left:0;top:10px;/* top:99px; */">y</div>''',
      css: r'''
/* div.x { color: #ff0000; } */
div.x { content: "}"; color: #0000ff; }
div.y { font-family: "Odd; Name}", serif; color: /* not here; */ #00ff00; }
div.y { content: "a \" ; b"; font-size: 20px; }
#page { background-image: url(img/a;b.png); }''',
    );

    final [x, y] = fixed.lines;
    expect(x.runs.single.style.color, const Color(0xFF0000FF));
    final yStyle = y.runs.single.style;
    expect(yStyle.fontFamily, 'Odd; Name}');
    expect(yStyle.color, const Color(0xFF00FF00));
    expect(yStyle.fontSize, 20, reason: 'an escaped quote ends no string');
    expect(y.position, const Offset(0, 10));
    expect(fixed.background.image, 'OEBPS/img/a;b.png');
  });

  test('at-rules are skipped whole, nested or ended by ; and HTML comment marks count for nothing', () {
    final line = page(
      '<div class="x" style="left:0;top:0">x</div>',
      css: '''
@charset "utf-8";
@import url("other.css");
<!--
@media print { div.x { color: #ff0000; } div.x { font-size: 99px; } }
div.x { color: #00ff00; }
-->
@page { margin: 0; }
div.x { font-size: 20px; }''',
    ).lines.single;

    expect(line.runs.single.style.color, const Color(0xFF00FF00));
    expect(line.runs.single.style.fontSize, 20);
  });

  test('a selector it cannot read drops its rule, and only that one', () {
    final line = page(
      '<div class="x" style="left:0;top:0">x</div>',
      css: '''
div.x, 1bad { color: #ff0000; }
div.x { font-size: 20px; }
div.x { letter-spacing: 2px;''',
    ).lines.single;

    final style = line.runs.single.style;
    expect(
      style.color,
      const Color(0xFF000000),
      reason: 'as in a browser, its good selector goes with it',
    );
    expect(style.fontSize, 20);
    expect(
      style.letterSpacing,
      2,
      reason: 'a block left open runs to the end of the stylesheet',
    );
  });

  test("finds the font files the page's stylesheets declare", () {
    final styles = open(
      {
        'html/page.xhtml': fixedPageXhtml(
          '',
          stylesheets: ['../styles/style.css'],
        ),
      },
      {
        'OEBPS/styles/style.css': '''
@font-face { font-family: "Gotham Book"; src: url(../fonts/Gotham-Book.otf); }
@font-face { font-family: 'Myriad'; src: url("../fonts/Myriad-Regular.ttf"); }
@font-face { font-family: Myriad; font-weight: bold;
  src: url(../fonts/Myriad-Bold.woff2) format("woff2"), url(../fonts/Myriad-Bold.OTF) format("opentype"); }
@font-face { font-family: "Web Only"; src: url(../fonts/web.woff); }''',
      },
    );

    expect(FixedPage.parse(styles, 0).fonts, {
      'Gotham Book': ['OEBPS/fonts/Gotham-Book.otf'],
      'Myriad': [
        'OEBPS/fonts/Myriad-Regular.ttf',
        'OEBPS/fonts/Myriad-Bold.OTF',
      ],
    });
  });

  test('the background comes from the page box, its picture found from its stylesheet', () {
    final styles = open(
      {
        'html/photo.xhtml': fixedPageXhtml(
          '<div id="page002" style="left:0;top:0"></div>',
          stylesheets: ['../styles/style.css'],
        ),
        'html/own.xhtml': fixedPageXhtml(
          '<div style="background-color:#000;background-image:url(img/a%20b.png)"></div>',
          stylesheets: ['../styles/style.css'],
        ),
        'html/plain.xhtml': fixedPageXhtml('<div></div>', stylesheets: []),
      },
      {
        'OEBPS/styles/style.css': '''
body { background-color: #FFFFFF; }
#page002 { background-image: url("../images/page002.jpg"); background-size: auto 100%;
  background-position: center; }''',
      },
    );

    final photo = FixedPage.parse(styles, 0).background;
    expect(photo.color, const Color(0xFFFFFFFF));
    expect(photo.image, 'OEBPS/images/page002.jpg');
    expect(photo.fit, BoxFit.fitHeight);
    expect(photo.alignment, Alignment.center);

    final own = FixedPage.parse(styles, 1).background;
    expect(own.color, const Color(0xFF000000));
    expect(own.image, 'OEBPS/html/img/a b.png');
    expect(own.fit, BoxFit.none);
    expect(own.alignment, Alignment.topLeft);

    final plain = FixedPage.parse(styles, 2).background;
    expect(plain.color, isNull);
    expect(plain.image, isNull);
  });

  test('reads background sizes and positions', () {
    const cases = {
      'background-size:cover': (BoxFit.cover, Alignment.topLeft),
      'background-size:contain;background-position:right bottom': (
        BoxFit.contain,
        Alignment.bottomRight,
      ),
      'background-size:100% 100%;background-position:top': (
        BoxFit.fill,
        Alignment.topCenter,
      ),
      'background-size:100%;background-position:bottom left': (
        BoxFit.fitWidth,
        Alignment.bottomLeft,
      ),
      'background-size:auto;background-position:25% 75%': (
        BoxFit.none,
        Alignment(-0.5, 0.5),
      ),
      'background-position:left': (BoxFit.none, Alignment.centerLeft),
      'background-size:50% 50%;background-position:10px 20px': (
        BoxFit.none,
        Alignment.topLeft,
      ),
    };
    final styles = open({
      for (final (index, style) in cases.keys.indexed)
        'p$index.xhtml': fixedPageXhtml(
          '<div style="background-image:url(a.png);$style"></div>',
        ),
    });

    for (final (index, MapEntry(key: style, value: expected))
        in cases.entries.indexed) {
      final background = FixedPage.parse(styles, index).background;
      expect((background.fit, background.alignment), expected, reason: style);
    }
  });

  test('a picture from outside the book, or none, shows nothing', () {
    final styles = open(
      {
        'data.xhtml': fixedPageXhtml(
          '''<div style="background-image:url('data:image/gif;base64,R0lGODlhAQABAAAAACw=')"></div>''',
        ),
        'web.xhtml': fixedPageXhtml(
          '<div style="background-image:url(https://example.com/a.jpg)"></div>',
        ),
        'none.xhtml': fixedPageXhtml('<div id="p" class="none"></div>'),
      },
      {
        'OEBPS/style.css': '#p { background-image: url(a.png); } #p.none { background-image: none; }',
      },
    );

    for (var index = 0; index < 3; index++) {
      expect(FixedPage.parse(styles, index).background.image, isNull);
    }
  });

  test("a page's lines: where they sit, their runs, their turn and their links", () {
    final styles = open(
      {
        'p1.xhtml': fixedPageXhtml('<div style="left:0;top:0">one</div>'),
        'p2.xhtml': fixedPageXhtml(
          '''
<div id="page" style="position:absolute;left:0px;top:0px;width:1000px;height:1500px;">
<div class="para">
<div class="l" style="left:10.5px;top:20px;/*right:5px;*/">Kale, <a href="p3.xhtml">11</a>, <a href="p1.xhtml#top">102–3</a></div>
<div class="side" style="left:990px;top:400px"><span>47</span> Breakfast</div>
<div class="l" style="left:10px;top:60px">   </div>
</div>
<a href="p3.xhtml"><div class="l" style="left:10px;top:80px">whole line</div></a>
<div class="l" style="left:10px;top:100px"><a href="https://example.com">web</a> <a href="notes.xhtml">notes</a></div>
<div class="l" style="left:0;top:120px">  cabbages
   &amp;   <span>crucifers</span>&nbsp;</div>
</div>
<div style="left:100px;top:200px"><div class="l" style="left:5px;top:5px">nested</div></div>''',
        ),
        'p3.xhtml': fixedPageXhtml('<div style="left:0;top:0">three</div>'),
      },
      {
        'OEBPS/style.css':
            'div.side { transform: rotate(-90deg); transform-origin: 0% 0%; }',
        'OEBPS/notes.xhtml': chapterXhtml('<p>Not in the reading order</p>'),
      },
    );

    final lines = FixedPage.parse(styles, 1).lines;
    List<(String, int?)> links(TextLine line) => [
      for (final run in line.runs) (run.text, run.link),
    ];
    expect(lines, hasLength(6));
    final [kale, side, whole, outside, collapsed, nested] = lines;

    expect(kale.position, const Offset(10.5, 20));
    expect(kale.placedByBottom, isFalse);
    expect(kale.transform, isTransform([1, 0, 0, 1, 0, 0]));
    expect(links(kale), [
      ('Kale, ', null),
      ('11', 2),
      (', ', null),
      ('102–3', 0),
    ]);

    expect(side.position, const Offset(990, 400));
    expect(side.transform, isTransform([0, -1, 1, 0, 0, 0]));
    expect(side.origin.alignment, Alignment.topLeft);
    expect(texts(side), ['47', ' Breakfast']);

    expect(whole.position, const Offset(10, 80));
    expect(links(whole), [('whole line', 2)]);

    expect(links(outside), [('web', null), (' ', null), ('notes', null)]);

    expect(collapsed.position, const Offset(0, 120));
    expect(texts(collapsed), ['cabbages & ', 'crucifers', ' ']);

    expect(
      nested.position,
      const Offset(105, 205),
      reason: 'a placed box moves the lines inside it',
    );
  });

  test('a line placed by bottom sits above the bottom of the nearest box that gives its height, '
      "else the page's", () {
    final fixed = page(
      '''
<div style="left:10px;bottom:100px">page</div>
<div style="left:10px;bottom:10%">page percent</div>
<div style="left:10px;top:20px;bottom:100px">both</div>
<div style="left:100px;top:200px;height:300px">
  <div style="left:5px;bottom:50px">boxed</div>
  <div style="left:5px;bottom:10%">boxed percent</div>
</div>
<div style="left:100px;top:200px"><div style="left:5px;bottom:50px">heightless box</div></div>
<div style="left:0;bottom:100px;height:400px">
  <div style="left:5px;top:10px">under the top of a box placed by bottom</div>
  <div style="left:5px;bottom:10px">above its bottom</div>
</div>
<div style="left:0;bottom:100px"><div style="left:5px;top:10px">in a heightless box placed by bottom</div></div>''',
    );

    expect(
      {
        for (final line in fixed.lines)
          texts(line).join(): (line.position, line.placedByBottom),
      },
      {
        'page': (const Offset(10, 1400), true),
        'page percent': (const Offset(10, 1350), true),
        'both': (const Offset(10, 20), false),
        'boxed': (const Offset(105, 450), true),
        'boxed percent': (const Offset(105, 470), true),
        'heightless box': (const Offset(105, 1450), true),
        'under the top of a box placed by bottom': (
          const Offset(5, 1010),
          false,
        ),
        'above its bottom': (const Offset(5, 1390), true),
        'in a heightless box placed by bottom': (const Offset(5, 1410), false),
      },
    );
  });

  test('an empty element closed with /> holds nothing', () {
    final fixed = page(
      '<div style="left:100px;top:100px"/><div style="left:10px;top:10px">after</div>',
    );

    expect(fixed.lines.single.position, const Offset(10, 10));
  });

  test('turns lines by rotate() in deg, rad and turn', () {
    final fixed = page(
      '''
<div style="left:0;top:0;transform:rotate(90deg)">deg</div>
<div style="left:0;top:0;transform:rotate(1.5rad)">rad</div>
<div style="left:0;top:0;transform:rotate(0.5turn)">turn</div>
<div style="left:0;top:0;transform:rotate(45deg);transform:skew(10deg)">skew</div>
<div style="left:0;top:0;transform:rotate(45deg);transform:none">none</div>
<div style="left:0;top:0;transform:rotate(45deg);transform:rotate(0)">zero</div>
<div style="left:0;top:0;transform:rotate(45deg);transform:rotate(90)">no unit</div>''',
    );

    final half = math.sqrt1_2;
    final [deg, rad, turn, skew, none, zero, noUnit] = fixed.lines;
    expect(deg.transform, isTransform([0, 1, -1, 0, 0, 0]));
    expect(
      rad.transform,
      isTransform([
        math.cos(1.5),
        math.sin(1.5),
        -math.sin(1.5),
        math.cos(1.5),
        0,
        0,
      ]),
    );
    expect(turn.transform, isTransform([-1, 0, 0, -1, 0, 0]));
    expect(
      skew.transform,
      isTransform([half, half, -half, half, 0, 0]),
      reason: 'a function it cannot apply drops the declaration',
    );
    expect(none.transform, isTransform([1, 0, 0, 1, 0, 0]));
    expect(zero.transform, isTransform([1, 0, 0, 1, 0, 0]));
    expect(
      noUnit.transform,
      isTransform([half, half, -half, half, 0, 0]),
      reason: 'only a zero may go without a unit',
    );
  });

  test(
    'transforms lines by scale(), matrix() and lists of them, the last first',
    () {
      final fixed = page(
        '''
<div style="left:0;top:0;transform:scale(0.25)">one value</div>
<div style="left:0;top:0;transform:scale(0.255, 0.25)">two values</div>
<div style="left:0;top:0;transform:matrix(0,-1,1,0,0, 0)">turned</div>
<div style="left:0;top:0;transform:matrix(1 0 0 1 10 20)">moved</div>
<div style="left:0;top:0;transform:matrix(1,0,0,1,10,0) scale(2)">scaled, then moved</div>
<div style="left:0;top:0;transform:scale(2) matrix(1,0,0,1,10,0)">moved, then scaled</div>
<div style="left:0;top:0;transform:SCALE(2) Rotate(90deg)">any case</div>
<div style="left:0;top:0;transform:scale(0.5);transform:scale(2) skew(10deg)">a function it cannot apply</div>
<div style="left:0;top:0;transform:scale(0.5);transform:scale(1, 2, 3)">three values</div>
<div style="left:0;top:0;transform:scale(0.5);transform:matrix(1,0,0,1,0)">five values</div>
<div style="left:0;top:0;transform:scale(0.5);transform:scale()">none</div>
<div style="left:0;top:0;transform:scale(0.5);transform:scale(2) junk">junk after</div>
<div style="left:0;top:0;transform:scale(0.5);transform:junk scale(2)">junk before</div>''',
      );

      expect(
        {for (final line in fixed.lines) texts(line).join(): line.transform},
        {
          'one value': isTransform([0.25, 0, 0, 0.25, 0, 0]),
          'two values': isTransform([0.255, 0, 0, 0.25, 0, 0]),
          'turned': isTransform([0, -1, 1, 0, 0, 0]),
          'moved': isTransform([1, 0, 0, 1, 10, 20]),
          'scaled, then moved': isTransform([2, 0, 0, 2, 10, 0]),
          'moved, then scaled': isTransform([2, 0, 0, 2, 20, 0]),
          'any case': isTransform([0, 2, -2, 0, 0, 0]),
          for (final dropped in [
            'a function it cannot apply',
            'three values',
            'five values',
            'none',
            'junk after',
            'junk before',
          ])
            dropped: isTransform([0.5, 0, 0, 0.5, 0, 0]),
        },
      );
    },
  );

  test('transforms a line around its transform-origin, its middle when it names none', () {
    final fixed = page(
      '''
<div style="left:0;top:0">unnamed</div>
<div style="left:0;top:0;transform-origin:bottom left">bottom left</div>
<div style="left:0;top:0;transform-origin:left bottom">left bottom</div>
<div style="left:0;top:0;transform-origin:top">top</div>
<div style="left:0;top:0;transform-origin:25% 75%">percentages</div>
<div style="left:0;top:0;transform-origin:0 0">zeros</div>
<div style="left:0;top:0;font-size:10px;transform-origin:10px 2em">lengths</div>
<div style="left:0;top:0;transform-origin:right 10px 5px">depth</div>
<div style="left:0;top:0;transform-origin:left top;transform-origin:sideways">unreadable</div>''',
    );

    expect(
      {
        for (final line in fixed.lines)
          texts(line).join(): (line.origin.alignment, line.origin.offset),
      },
      {
        'unnamed': (Alignment.center, Offset.zero),
        'bottom left': (Alignment.bottomLeft, Offset.zero),
        'left bottom': (Alignment.bottomLeft, Offset.zero),
        'top': (Alignment.topCenter, Offset.zero),
        'percentages': (const Alignment(-0.5, 0.5), Offset.zero),
        'zeros': (Alignment.topLeft, Offset.zero),
        'lengths': (Alignment.topLeft, const Offset(10, 20)),
        'depth': (Alignment.topRight, const Offset(0, 10)),
        'unreadable': (Alignment.topLeft, Offset.zero),
      },
    );
  });

  test('a page as a PDF converter writes it: its picture behind, lines placed by bottom, set large and scaled down', () {
    final fixed = page(
      '''
<div id="page008" style="position:absolute;left:0px;top:0px;width:1000px;height:1500px;">
<div id="t1_8" class="t s1_8">The weather in</div>
<div id="t2_8" class="t s1_8">the heart of winter</div>
<div id="tv_8" class="t s1_8">47 Breakfast</div>
</div>''',
      css: '''
body {background-color:#FFFFFF;position:absolute;top:0px;left:0px;margin:0px;width:1000 px;height:1500 px;}
#cover {background-image:url("cover.jpg");background-size:auto100%;background-repeat:no-repeat;background-position:center;position:absolute;width:1000 px;height:1500 px;}
#page008 {background-image:url("page008.jpg");background-size:auto100%;background-repeat:no-repeat;background-position:center;position:absolute;width:1000 px;height:1500 px;}
.t {
	-webkit-transform-origin: bottom left;
	transform-origin: bottom left;
	-webkit-transform: scale(0.25);
	transform: scale(0.25);
	z-index: 2;
	position: absolute;
	white-space: pre;
}
#t1_8{left:190px;bottom:1401px;letter-spacing:1.1px;word-spacing:-0.1px;}
#t2_8{left:190px;bottom:1361px;}
#tv_8{left:60px;bottom:400px;transform: matrix(0,-1,1,0,0, 0);}
.s1_8{
	FONT-SIZE: 101.3px;
	FONT-FAMILY: Palatino-Italic__j;
	color: rgb(35,31,32);
}''',
    );

    expect(fixed.background.image, 'OEBPS/page008.jpg');
    expect(fixed.background.alignment, Alignment.center);
    expect(fixed.background.color, const Color(0xFFFFFFFF));

    final [weather, winter, side] = fixed.lines;
    expect(texts(weather), ['The weather in']);
    expect(weather.position, const Offset(190, 99));
    expect(weather.placedByBottom, isTrue);
    expect(weather.transform, isTransform([0.25, 0, 0, 0.25, 0, 0]));
    expect(weather.origin.alignment, Alignment.bottomLeft);
    expect(weather.style.fontSize, 101.3);
    expect(weather.style.fontFamily, 'Palatino-Italic__j');
    expect(weather.style.color, const Color(0xFF231F20));

    expect(winter.position, const Offset(190, 139));

    expect(side.position, const Offset(60, 1100));
    expect(
      side.transform,
      isTransform([0, -1, 1, 0, 0, 0]),
      reason: "an id's transform outweighs the class's",
    );
    expect(side.origin.alignment, Alignment.bottomLeft);
  });

  test('the size comes from the viewport, else from the page box', () {
    final styles = open(
      {
        'viewport.xhtml': fixedPageXhtml(
          '<div style="width:10px;height:10px"></div>',
          viewport: 'width=1116, height=1450',
        ),
        'box.xhtml': fixedPageXhtml('<div id="page"></div>', viewport: null),
        'none.xhtml': fixedPageXhtml('<div></div>', viewport: null),
        'half.xhtml': fixedPageXhtml('<div></div>', viewport: 'width=800'),
      },
      {'OEBPS/style.css': '#page { width: 50em; height: 600px; }'},
    );

    expect(FixedPage.parse(styles, 0).size, const Size(1116, 1450));
    expect(FixedPage.parse(styles, 1).size, const Size(800, 600));
    expect(() => FixedPage.parse(styles, 2), throwsFormatException);
    expect(() => FixedPage.parse(styles, 3), throwsFormatException);
  });

  test('a page that is not well-formed XHTML, or has no body, is a FormatException', () {
    final styles = open({
      'broken.xhtml': '<html xmlns="http://www.w3.org/1999/xhtml"><body><div>open</body></html>',
      'bodiless.xhtml':
          '<html xmlns="http://www.w3.org/1999/xhtml"><head></head></html>',
    });

    expect(() => FixedPage.parse(styles, 0), throwsFormatException);
    expect(() => FixedPage.parse(styles, 1), throwsFormatException);
  });
}
