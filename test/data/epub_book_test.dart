import 'dart:convert';
import 'dart:io';

import 'package:bookserver/data/epub_book.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test("gives what is inside a chapter's body, not its head", () {
    final book = open({
      'META-INF/container.xml': containerXml(),
      'OEBPS/content.opf': packageXml({'one': 'one.xhtml'}, ['one']),
      'OEBPS/one.xhtml': chapterXhtml(
        '<h1>Chapter 1</h1><p>It begins&nbsp;here.</p>',
      ),
    });
    addTearDown(book.close);

    final body = book.chapterBody(0);
    expect(body, contains('<h1>Chapter 1</h1>'));
    expect(body, contains('It begins'));
    expect(body, isNot(contains('Not part of the text')));
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
