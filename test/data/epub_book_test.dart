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
}
