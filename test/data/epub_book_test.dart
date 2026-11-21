import 'dart:convert';
import 'dart:io';

import 'package:bookserver/data/epub_book.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

import '../support/epubs.dart';
import '../support/images.dart';

void main() {
  late Directory folder;
  setUp(() => folder = Directory.systemTemp.createTempSync('bookserver-epub-'));
  tearDown(() => folder.deleteSync(recursive: true));

  EpubBook open(Map<String, Object> files) =>
      EpubBook.open(writeEpub(folder, files));

  test(
    'lists the chapters in spine order, resolved against the package file',
    () {
      final book = open({
        'META-INF/container.xml': containerXml(),
        'OEBPS/content.opf': packageXml(
          {
            'one': 'text/one.xhtml',
            'two': '../extra/two.xhtml',
            'three': 'text/chapter%203.xhtml#start',
          },
          ['two', 'one', 'three'],
        ),
        'OEBPS/text/one.xhtml': chapterXhtml('<p>One</p>'),
        'extra/two.xhtml': chapterXhtml('<p>Two</p>'),
        'OEBPS/text/chapter 3.xhtml': chapterXhtml('<p>Three</p>'),
      });
      addTearDown(book.close);

      expect(book.chapters, [
        'extra/two.xhtml',
        'OEBPS/text/one.xhtml',
        'OEBPS/text/chapter 3.xhtml',
      ]);
    },
  );

  test('knows a book of fixed pages from one whose text flows', () {
    Map<String, Object> files({required bool fixedLayout}) => {
      'META-INF/container.xml': containerXml(),
      'OEBPS/content.opf': packageXml(
        {'one': 'one.xhtml'},
        ['one'],
        fixedLayout: fixedLayout,
      ),
      'OEBPS/one.xhtml': chapterXhtml('<p>One</p>'),
    };

    final fixed = open(files(fixedLayout: true));
    addTearDown(fixed.close);
    expect(fixed.isFixedLayout, isTrue);

    final flowing = EpubBook.open(
      File('${folder.path}/flowing.epub')
        ..writeAsBytesSync(epubBytes(files(fixedLayout: false))),
    );
    addTearDown(flowing.close);
    expect(flowing.isFixedLayout, isFalse);
  });

  test('reads whether the spine runs the pages right to left', () {
    for (final (index, (progression, rightToLeft)) in [
      ('rtl', true),
      (' rtl ', true),
      ('ltr', false),
      ('default', false),
      (null, false),
    ].indexed) {
      final book = EpubBook.open(
        File('${folder.path}/book-$index.epub')..writeAsBytesSync(
          epubBytes({
            'META-INF/container.xml': containerXml(),
            'OEBPS/content.opf': packageXml(
              {'one': 'one.xhtml'},
              ['one'],
              fixedLayout: true,
              pageProgression: progression,
            ),
            'OEBPS/one.xhtml': chapterXhtml('<p>One</p>'),
          }),
        ),
      );
      addTearDown(book.close);
      expect(book.isRightToLeft, rightToLeft, reason: '$progression');
    }
  });

  test('leaves out what the spine marks as outside the reading order', () {
    final book = open({
      'META-INF/container.xml': containerXml(),
      'OEBPS/content.opf': packageXml(
        {'cover': 'cover.xhtml', 'one': 'one.xhtml'},
        ['cover', 'one'],
      ).replaceFirst('idref="cover"', 'idref="cover" linear="no"'),
      'OEBPS/cover.xhtml': chapterXhtml('<img src="cover.jpg"/>'),
      'OEBPS/one.xhtml': chapterXhtml('<p>One</p>'),
    });
    addTearDown(book.close);

    expect(book.chapters, ['OEBPS/one.xhtml']);
  });

  test('reads a package file whose elements carry a namespace prefix', () {
    final book = open({
      'META-INF/container.xml': containerXml('content.opf'),
      'content.opf':
          '<opf:package xmlns:opf="http://www.idpf.org/2007/opf" version="2.0">'
          '<opf:manifest><opf:item id="one" href="one.xhtml"/></opf:manifest>'
          '<opf:spine><opf:itemref idref="one"/></opf:spine>'
          '</opf:package>',
      'one.xhtml': chapterXhtml('<p>One</p>'),
    });
    addTearDown(book.close);

    expect(book.chapters, ['one.xhtml']);
  });

  test("gives the blocks inside a chapter's body, not its head", () {
    final book = open({
      'META-INF/container.xml': containerXml(),
      'OEBPS/content.opf': packageXml(
        {'one': 'one.xhtml', 'empty': 'empty.xhtml'},
        ['one', 'empty'],
      ),
      'OEBPS/one.xhtml': chapterXhtml('<h1>Chapter 1</h1><p>It begins.</p>'),
      'OEBPS/empty.xhtml': chapterXhtml(' '),
    });
    addTearDown(book.close);

    expect(book.chapterBlocks(0), ['<h1>Chapter 1</h1>', '<p>It begins.</p>']);
    expect(book.chapterBlocks(1), isEmpty);
  });

  test('splits a chapter into blocks, opening up the wrappers around them', () {
    final book = open({
      'META-INF/container.xml': containerXml(),
      'OEBPS/content.opf': packageXml({'one': 'one.xhtml'}, ['one']),
      'OEBPS/one.xhtml': chapterXhtml(
        '<section class="chapter" title="Three &amp; more">'
        '<div class="titlepage"><div><h1 class="title">Three</h1></div></div>'
        '<p>One</p> <a id="page5"/> <!-- a note -->'
        '<p>Two <em>and</em> more</p>'
        'Loose <b>text</b><img src="a.png"/>'
        '<div class="x"/>'
        '<ul><li>a</li></ul>'
        '</section>',
      ),
    });
    addTearDown(book.close);

    const section = '<section class="chapter" title="Three &amp; more">';
    expect(book.chapterBlocks(0), [
      '$section<div class="titlepage"><div><h1 class="title">Three</h1></div></div></section>',
      '$section<p>One</p></section>',
      '$section<p>Two <em>and</em> more</p></section>',
      '${section}Loose <b>text</b><img src="a.png"/></section>',
      '$section<ul><li>a</li></ul></section>',
    ]);
  });

  test('reads a chapter as XML: a tag closed with /> holds nothing', () {
    final book = open({
      'META-INF/container.xml': containerXml(),
      'OEBPS/content.opf': packageXml({'one': 'one.xhtml'}, ['one']),
      'OEBPS/one.xhtml': chapterXhtml(
        '<p>Before<a id="page12"/> after the anchor.</p><div class="x"/><p>Next</p>'
        '<p>One<br/>two &amp; three&nbsp;four</p>',
      ),
    });
    addTearDown(book.close);

    final blocks = book.chapterBlocks(0);
    expect(
      blocks,
      hasLength(3),
      reason: 'the empty <div class="x"/> shows nothing',
    );
    // Read back the way the reader's HTML view reads them.
    final [before, next, lines] = [
      for (final block in blocks) html.parse(block).body!,
    ];
    expect(before.querySelector('a#page12')!.nodes, isEmpty);
    expect(before.text, 'Before after the anchor.');
    expect(next.text, 'Next');
    expect(lines.querySelectorAll('br'), hasLength(1));
    expect(lines.text, 'Onetwo & three${String.fromCharCode(0xA0)}four');
  });

  test('a chapter that is no well-formed XML is one block', () {
    final book = open({
      'META-INF/container.xml': containerXml(),
      'OEBPS/content.opf': packageXml(
        {'unclosed': 'unclosed.xhtml', 'prefixed': 'prefixed.xhtml'},
        ['unclosed', 'prefixed'],
      ),
      'OEBPS/unclosed.xhtml': '<html><body><p>First<br><p>Second</body></html>',
      'OEBPS/prefixed.xhtml': '<html><body><section epub:type="chapter"><p>Typed</p></section></body></html>',
    });
    addTearDown(book.close);

    final unclosed = html.parse(book.chapterBlocks(0).single).body!;
    expect(
      [for (final paragraph in unclosed.querySelectorAll('p')) paragraph.text],
      ['First', 'Second'],
    );
    expect(book.chapterBlocks(1).single, contains('Typed'));
  });

  test('reads any file in the book, and nothing for one it lacks', () {
    final book = open({
      'META-INF/container.xml': containerXml(),
      'OEBPS/content.opf': packageXml({'one': 'one.xhtml'}, ['one']),
      'OEBPS/one.xhtml': chapterXhtml('<img src="images/dish.png"/>'),
      'OEBPS/images/dish.png': onePixelPng,
    });
    addTearDown(book.close);

    expect(book.read('OEBPS/images/dish.png'), onePixelPng);
    expect(book.read('OEBPS/images/missing.png'), isNull);
    expect(
      utf8.decode(book.read('META-INF/container.xml')!),
      contains('OEBPS/content.opf'),
    );
  });

  test('refuses what is no readable EPUB', () {
    final valid = <String, Object>{
      'META-INF/container.xml': containerXml(),
      'OEBPS/content.opf': packageXml({'one': 'one.xhtml'}, ['one']),
      'OEBPS/one.xhtml': chapterXhtml('<p>One</p>'),
    };
    final broken = <String, Map<String, Object>>{
      'no container': {...valid}..remove('META-INF/container.xml'),
      'a container naming no package file': {
        ...valid,
        'META-INF/container.xml': '<container><rootfiles/></container>',
      },
      'no package file': {...valid}..remove('OEBPS/content.opf'),
      'a package file that is no XML': {
        ...valid,
        'OEBPS/content.opf': 'not <xml',
      },
      'a spine without chapters': {
        ...valid,
        'OEBPS/content.opf': packageXml({'one': 'one.xhtml'}, []),
      },
      'a chapter missing from the archive': {...valid}
        ..remove('OEBPS/one.xhtml'),
    };
    for (final MapEntry(key: problem, value: files) in broken.entries) {
      expect(() => open(files), throwsFormatException, reason: problem);
    }

    final notAZip = File('${folder.path}/book.epub')
      ..writeAsStringSync('plain text, no zip');
    expect(() => EpubBook.open(notAZip), throwsFormatException);
  });

  group('table of contents', () {
    /// Opens a book of two chapters, `OEBPS/text/one.xhtml` and `two.xhtml`, under [name], with
    /// [extra] files and the manifest [items] besides; [properties] and [toc] go to the package.
    EpubBook openWithContents(
      String name, {
      Map<String, String> items = const {},
      Map<String, Object> extra = const {},
      Map<String, String> properties = const {},
      String? toc,
    }) {
      final book = EpubBook.open(
        File('${folder.path}/$name.epub')..writeAsBytesSync(
          epubBytes({
            'META-INF/container.xml': containerXml(),
            'OEBPS/content.opf': packageXml(
              {'one': 'text/one.xhtml', 'two': 'text/two.xhtml', ...items},
              ['one', 'two'],
              properties: properties,
              toc: toc,
            ),
            'OEBPS/text/one.xhtml': chapterXhtml('<p>One</p>'),
            'OEBPS/text/two.xhtml': chapterXhtml('<p>Two</p>'),
            ...extra,
          }),
        ),
      );
      addTearDown(book.close);
      return book;
    }

    const navList = '''
<ol>
  <li><a href="../text/one.xhtml">Chapter
      One</a></li>
  <li><span>Part Two</span>
    <ol>
      <li><a href="../text/two.xhtml#scene%202">Scene 2</a></li>
      <li><a href="../text/two.xhtml#end">The End</a></li>
    </ol>
  </li>
  <li><a href="https://example.com/more">Elsewhere</a></li>
</ol>''';

    const navEntries = [
      TocEntry(title: 'Chapter One', file: 'OEBPS/text/one.xhtml'),
      TocEntry(
        title: 'Part Two',
        children: [
          TocEntry(
            title: 'Scene 2',
            file: 'OEBPS/text/two.xhtml',
            anchor: 'scene 2',
          ),
          TocEntry(
            title: 'The End',
            file: 'OEBPS/text/two.xhtml',
            anchor: 'end',
          ),
        ],
      ),
      TocEntry(title: 'Elsewhere'),
    ];

    const ncxPoints = '''
<navPoint id="p1" playOrder="1">
  <navLabel><text>One</text></navLabel><content src="text/one.xhtml"/>
  <navPoint id="p2" playOrder="2">
    <navLabel><text>One, part two</text></navLabel><content src="text/one.xhtml#part2"/>
  </navPoint>
</navPoint>
<navPoint id="p3" playOrder="3">
  <navLabel><text>Two</text></navLabel><content src="text/two.xhtml"/>
</navPoint>''';

    const ncxEntries = [
      TocEntry(
        title: 'One',
        file: 'OEBPS/text/one.xhtml',
        children: [
          TocEntry(
            title: 'One, part two',
            file: 'OEBPS/text/one.xhtml',
            anchor: 'part2',
          ),
        ],
      ),
      TocEntry(title: 'Two', file: 'OEBPS/text/two.xhtml'),
    ];

    Map<String, Object> navFile(String content) => {
      'OEBPS/nav/nav.xhtml': content,
    };
    Map<String, Object> ncxFile(String content) => {'OEBPS/toc.ncx': content};

    test(
      "reads an EPUB 3 navigation file's contents: headings without a target, nesting, anchors, "
      'links resolved against the file, a link out of the book going nowhere',
      () {
        final book = openWithContents(
          'nav',
          items: {'nav': 'nav/nav.xhtml'},
          properties: {'nav': 'nav'},
          extra: navFile(navXhtml(navList)),
        );

        expect(book.toc, navEntries);
      },
    );

    test('reads an EPUB 2 NCX when the book has no navigation file', () {
      final book = openWithContents(
        'ncx',
        items: {'ncx': 'toc.ncx'},
        toc: 'ncx',
        extra: ncxFile(ncxXml(ncxPoints)),
      );

      expect(book.toc, ncxEntries);
    });

    test('a book with both reads the navigation file', () {
      final book = openWithContents(
        'both',
        items: {'nav': 'nav/nav.xhtml', 'ncx': 'toc.ncx'},
        properties: {'nav': 'nav'},
        toc: 'ncx',
        extra: {...navFile(navXhtml(navList)), ...ncxFile(ncxXml(ncxPoints))},
      );

      expect(book.toc, navEntries);
    });

    test('a broken navigation file leaves the NCX; a book with neither, or with both broken, has none', () {
      final broken = {
        ...navFile('<html><nav epub:type="toc"><ol><li>'),
        ...ncxFile(ncxXml(ncxPoints)),
      };
      expect(
        openWithContents(
          'broken-nav',
          items: {'nav': 'nav/nav.xhtml', 'ncx': 'toc.ncx'},
          properties: {'nav': 'nav'},
          toc: 'ncx',
          extra: broken,
        ).toc,
        ncxEntries,
      );

      expect(openWithContents('neither').toc, isEmpty);
      expect(
        openWithContents(
          'both-broken',
          items: {'nav': 'nav/nav.xhtml', 'ncx': 'toc.ncx'},
          properties: {'nav': 'nav'},
          toc: 'ncx',
          extra: {...navFile('not xml <'), ...ncxFile('<ncx>')},
        ).toc,
        isEmpty,
      );
      expect(
        openWithContents(
          'missing-file',
          items: {'nav': 'nav/nav.xhtml'},
          properties: {'nav': 'nav'},
        ).toc,
        isEmpty,
        reason: 'named in the package but not in the archive',
      );
    });

    test('an entry for a file outside the reading order keeps its file', () {
      final book = EpubBook.open(
        File('${folder.path}/notes.epub')..writeAsBytesSync(
          epubBytes({
            'META-INF/container.xml': containerXml(),
            'OEBPS/content.opf': packageXml(
              {'nav': 'nav.xhtml', 'one': 'one.xhtml', 'notes': 'notes.xhtml'},
              ['one', 'notes'],
              properties: {'nav': 'nav'},
            ).replaceFirst('idref="notes"', 'idref="notes" linear="no"'),
            'OEBPS/nav.xhtml': navXhtml(
              '<ol><li><a href="notes.xhtml">Notes</a></li></ol>',
            ),
            'OEBPS/one.xhtml': chapterXhtml('<p>One</p>'),
            'OEBPS/notes.xhtml': chapterXhtml('<p>Notes</p>'),
          }),
        ),
      );
      addTearDown(book.close);

      expect(book.toc, [
        const TocEntry(title: 'Notes', file: 'OEBPS/notes.xhtml'),
      ]);
      expect(book.chapters, isNot(contains('OEBPS/notes.xhtml')));
    });
  });

  group('anchors', () {
    test('each lands on the block that holds it, or, holding no text, on the first block after it', () {
      final book = open({
        'META-INF/container.xml': containerXml(),
        'OEBPS/content.opf': packageXml({'one': 'one.xhtml'}, ['one']),
        'OEBPS/one.xhtml': chapterXhtml('''
<a id="page1"/>
<h1 id="title">Title</h1>
<section id="part"><p>First <span id="inline">word</span></p><p id="second">Second</p></section>
Loose <b id="bold">text</b>
<p>Third <a name="old"/>here</p>
<p id="title">Again</p>
<div id="empty"></div>
<a id="page9"/>'''),
      });
      addTearDown(book.close);

      final chapter = book.chapter(0);

      expect(chapter.blocks, hasLength(6));
      expect(chapter.anchors, {
        'page1': 0,
        'title': 0,
        'part': 1,
        'inline': 1,
        'second': 2,
        'bold': 3,
        'old': 4,
        'empty': 5,
        'page9': 5,
      });
      expect(book.chapterBlocks(0), chapter.blocks);
    });

    test(
      'a chapter that is no well-formed XML lands its anchors on its one block',
      () {
        final book = open({
          'META-INF/container.xml': containerXml(),
          'OEBPS/content.opf': packageXml({'one': 'one.xhtml'}, ['one']),
          'OEBPS/one.xhtml':
              '<html><body><p id="a">One<p id="b">Two</body></html>',
        });
        addTearDown(book.close);

        expect(book.chapter(0).anchors, {'a': 0, 'b': 0});
      },
    );
  });
}
