import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';

/// An entry of a book's table of contents: its title, where it goes — a file of the book and an
/// `id` in it — and the entries under it.
@immutable
class TocEntry {
  const TocEntry({
    required this.title,
    this.file,
    this.anchor,
    this.children = const [],
  });

  final String title;

  /// The archive path of the file it goes to; null for a heading that goes nowhere.
  final String? file;

  /// The `id` in [file] it goes to; null for the file's start.
  final String? anchor;

  final List<TocEntry> children;

  @override
  bool operator ==(Object other) =>
      other is TocEntry &&
      other.title == title &&
      other.file == file &&
      other.anchor == anchor &&
      listEquals(other.children, children);

  @override
  int get hashCode =>
      Object.hash(title, file, anchor, Object.hashAll(children));

  @override
  String toString() =>
      'TocEntry($title, $file${anchor == null ? '' : '#$anchor'}'
      '${children.isEmpty ? '' : ', $children'})';
}

/// A chapter as the flowing reader shows it: its blocks of HTML, and the block each anchor in it
/// lands on.
typedef ChapterBlocks = ({List<String> blocks, Map<String, int> anchors});

/// An EPUB file opened for reading: its chapters in reading order, and any file in it, read from
/// the archive only when asked for.
class EpubBook {
  EpubBook._(
    this._input,
    this._archive,
    this.chapters, {
    required this.isFixedLayout,
    required this.isRightToLeft,
    required this._tocFiles,
  });

  /// Opens the EPUB at [file]. A file that isn't a readable EPUB throws a [FormatException].
  static EpubBook open(File file) {
    final input = InputFileStream(file.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final packagePath = _packagePath(
        _xmlAt(archive, 'META-INF/container.xml'),
      );
      final package = _xmlAt(archive, packagePath);
      final chapters = _readingOrder(packagePath, package);
      for (final chapter in chapters) {
        if (archive.find(chapter) == null) {
          throw FormatException('The book has no chapter $chapter.');
        }
      }
      return EpubBook._(
        input,
        archive,
        chapters,
        isFixedLayout: _isFixedLayout(package),
        isRightToLeft: _isRightToLeft(package),
        tocFiles: _tocFilesIn(packagePath, package),
      );
    } on Exception catch (error) {
      input.closeSync();
      throw error is FormatException
          ? error
          : FormatException('Not a readable EPUB: $error');
    }
  }

  final InputFileStream _input;
  final Archive _archive;

  /// The archive paths of the chapters, in reading order.
  final List<String> chapters;

  /// Whether the book is laid out as fixed pages, like print, rather than as text that flows.
  final bool isFixedLayout;

  /// Whether the book's pages run right to left, as a manga's do.
  final bool isRightToLeft;

  /// Where the book's table of contents is: its EPUB 3 navigation file and its EPUB 2 NCX.
  final ({String? nav, String? ncx}) _tocFiles;

  /// The book's own table of contents: its navigation file's, else its NCX's. None for a book with
  /// neither, or whose one can't be read: a book without contents still opens.
  late final List<TocEntry> toc = _readToc();

  /// The file at [path] in the archive, or null when the book has none there.
  Uint8List? read(String path) => _bytesAt(_archive, path);

  /// What chapter [index]'s `<body>` holds, as blocks of HTML in reading order — paragraphs,
  /// headings, lists — each inside the tags of the elements that wrap it, so their styles still
  /// apply.
  List<String> chapterBlocks(int index) => chapter(index).blocks;

  /// Chapter [index] as [chapterBlocks] makes it, with the block each anchor in it lands on — an
  /// element's `id`, an `<a>`'s `name`: the block that holds it, or for one that holds no text,
  /// such as a page marker or a wrapper's start, the first block after it.
  ChapterBlocks chapter(int index) {
    final text = utf8.decode(read(chapters[index])!, allowMalformed: true);
    final XmlDocument document;
    try {
      // XHTML read as XML: an HTML parser ignores `/>` on a tag like `<a id="page12"/>`, which
      // then swallows the text after it.
      document = XmlDocument.parse(
        text,
        entityMapping: const XmlDefaultEntityMapping.html5(),
      );
    } on FormatException {
      // A chapter that isn't well-formed XML still shows, as one block an HTML parser makes out.
      final body = html.parse(text).body;
      final inner = body?.innerHtml.trim() ?? '';
      if (body == null || inner.isEmpty) {
        return (blocks: const [], anchors: const {});
      }
      return (
        blocks: [inner],
        anchors: {
          for (final element in body.querySelectorAll('[id]')) element.id: 0,
        },
      );
    }
    final body = document.rootElement.childElements
        .where((element) => element.localName == 'body')
        .firstOrNull;
    if (body == null) {
      return (blocks: const [], anchors: const {});
    }
    // Written for an HTML parser to read again, which ignores `/>` on an element that can hold
    // content.
    for (final element in body.descendantElements) {
      element.isSelfClosing = _voidElements.contains(element.localName);
    }
    final made = _Chapter();
    _addBlocks(body, '', '', made);
    made.endWithWaiting();
    return (blocks: made.blocks, anchors: made.anchors);
  }

  List<TocEntry> _readToc() {
    for (final (path, entries) in [
      (_tocFiles.nav, _navEntries),
      (_tocFiles.ncx, _ncxEntries),
    ]) {
      final bytes = path == null ? null : read(path);
      if (path == null || bytes == null) {
        continue;
      }
      try {
        final found = entries(
          XmlDocument.parse(
            utf8.decode(bytes, allowMalformed: true),
            entityMapping: const XmlDefaultEntityMapping.html5(),
          ),
          Uri(path: path),
        );
        if (found.isNotEmpty) {
          return found;
        }
      } on FormatException {
        // A broken one is no contents; the other kind may still be there.
      }
    }
    return const [];
  }

  /// Lets go of the file; nothing can be read after.
  void close() => _input.closeSync();
}

/// A chapter's blocks as they are made, and the block each anchor lands on.
class _Chapter {
  final blocks = <String>[];
  final anchors = <String, int>{};

  /// Anchors met before any block to hold them: they land on the next one.
  final _waiting = <String>[];

  /// Adds a block holding the anchors [inside], which the waiting ones land on too.
  void add(String block, Iterable<String> inside) {
    final index = blocks.length;
    blocks.add(block);
    for (final anchor in [..._waiting, ...inside]) {
      // The first of two equal ids is the one a link finds.
      anchors.putIfAbsent(anchor, () => index);
    }
    _waiting.clear();
  }

  void wait(Iterable<String> anchors) => _waiting.addAll(anchors);

  /// Lands the anchors after the last block on it.
  void endWithWaiting() {
    if (blocks.isNotEmpty) {
      for (final anchor in _waiting) {
        anchors.putIfAbsent(anchor, () => blocks.length - 1);
      }
    }
    _waiting.clear();
  }
}

/// Adds what [parent] holds to [chapter], each block written between [opening] and [closing], the
/// tags of the elements around it. A wrapper such as `<section>` is opened up into the blocks
/// inside it; loose text and inline elements between blocks become a block of their own.
void _addBlocks(
  XmlElement parent,
  String opening,
  String closing,
  _Chapter chapter,
) {
  final loose = <XmlNode>[];
  void addLoose() {
    final inside = [for (final node in loose) ..._anchorsIn(node)];
    if (loose.any(_shows)) {
      chapter.add(
        '$opening${loose.map((node) => node.toXmlString()).join()}$closing',
        inside,
      );
    } else {
      chapter.wait(inside);
    }
    loose.clear();
  }

  for (final node in parent.children) {
    if (node is XmlElement && _wrappers.contains(node.localName)) {
      addLoose();
      // The wrapper's own anchor lands on its first block.
      chapter.wait(_anchorsOf(node));
      final attributes = node.attributes
          .map((attribute) => ' $attribute')
          .join();
      final name = node.name.qualified;
      _addBlocks(
        node,
        '$opening<$name$attributes>',
        '</$name>$closing',
        chapter,
      );
    } else if (node is XmlElement && _blockElements.contains(node.localName)) {
      addLoose();
      chapter.add('$opening${node.toXmlString()}$closing', _anchorsIn(node));
    } else {
      loose.add(node);
    }
  }
  addLoose();
}

/// The anchors [element] itself names: its `id`, and an `<a>`'s `name`.
Iterable<String> _anchorsOf(XmlElement element) => [
  ?element.getAttribute('id'),
  if (element.localName == 'a') ?element.getAttribute('name'),
];

/// The anchors in [node] and every element inside it.
Iterable<String> _anchorsIn(XmlNode node) => node is XmlElement
    ? [
        ..._anchorsOf(node),
        for (final element in node.descendantElements) ..._anchorsOf(element),
      ]
    : const [];

/// Where the book's table of contents is: the EPUB 3 navigation file, the manifest item whose
/// `properties` include `nav`, and the EPUB 2 NCX, the item the spine's `toc` names.
({String? nav, String? ncx}) _tocFilesIn(
  String packagePath,
  XmlDocument package,
) {
  final base = Uri(path: packagePath);
  final items = package.findAllElements('item', namespaceUri: '*').toList();
  String? pathOf(XmlElement? item) => switch (item?.getAttribute('href')) {
    final href? => Uri.decodeComponent(base.resolve(href).path),
    null => null,
  };
  final nav = items
      .where(
        (item) => (item.getAttribute('properties') ?? '')
            .split(_whiteSpace)
            .contains('nav'),
      )
      .firstOrNull;
  final tocId = package
      .findAllElements('spine', namespaceUri: '*')
      .firstOrNull
      ?.getAttribute('toc');
  final ncx = items
      .where((item) => tocId != null && item.getAttribute('id') == tocId)
      .firstOrNull;
  return (nav: pathOf(nav), ncx: pathOf(ncx));
}

/// The entries of an EPUB 3 navigation file's `<nav epub:type="toc">`: each `<li>` an `<a>` that
/// goes somewhere or a `<span>` heading that doesn't, with its own `<ol>` beneath.
List<TocEntry> _navEntries(XmlDocument nav, Uri base) {
  final toc = nav
      .findAllElements('nav', namespaceUri: '*')
      .where(
        (element) =>
            (element.getAttribute('type', namespaceUri: _opsNamespace) ?? '')
                .split(_whiteSpace)
                .contains('toc'),
      )
      .firstOrNull;
  final list = toc == null ? null : _child(toc, 'ol');
  return list == null ? const [] : _navList(list, base);
}

List<TocEntry> _navList(XmlElement list, Uri base) => [
  for (final item in list.childElements.where((e) => e.localName == 'li'))
    ?_navItem(item, base),
];

TocEntry? _navItem(XmlElement item, Uri base) {
  final label = _child(item, 'a') ?? _child(item, 'span');
  final title = _collapsed(label?.innerText ?? '');
  final below = _child(item, 'ol');
  final children = below == null ? const <TocEntry>[] : _navList(below, base);
  if (title.isEmpty && children.isEmpty) {
    return null;
  }
  final (file, anchor) = _target(
    label?.localName == 'a' ? label?.getAttribute('href') : null,
    base,
  );
  return TocEntry(title: title, file: file, anchor: anchor, children: children);
}

/// The entries of an EPUB 2 NCX: its `navMap`'s `navPoint`s, each with its label, the place its
/// `content` goes to and the `navPoint`s within it.
List<TocEntry> _ncxEntries(XmlDocument ncx, Uri base) {
  final map = ncx.findAllElements('navMap', namespaceUri: '*').firstOrNull;
  return map == null ? const [] : _ncxPoints(map, base);
}

List<TocEntry> _ncxPoints(XmlElement parent, Uri base) => [
  for (final point in parent.childElements.where(
    (e) => e.localName == 'navPoint',
  ))
    ?_ncxPoint(point, base),
];

TocEntry? _ncxPoint(XmlElement point, Uri base) {
  final label = _child(point, 'navLabel');
  final title = _collapsed(
    (label == null ? null : _child(label, 'text'))?.innerText ?? '',
  );
  final children = _ncxPoints(point, base);
  if (title.isEmpty && children.isEmpty) {
    return null;
  }
  final (file, anchor) = _target(
    _child(point, 'content')?.getAttribute('src'),
    base,
  );
  return TocEntry(title: title, file: file, anchor: anchor, children: children);
}

/// The first child element of [parent] called [name], in any namespace.
XmlElement? _child(XmlElement parent, String name) =>
    parent.childElements.where((e) => e.localName == name).firstOrNull;

/// Where [link], written in the file at [base], goes in the book: an archive path and an anchor
/// in it. Nowhere for no link, or a link out of the book.
(String?, String?) _target(String? link, Uri base) {
  if (link == null || link.trim().isEmpty) {
    return (null, null);
  }
  final Uri target;
  try {
    target = base.resolve(link.trim());
  } on FormatException {
    return (null, null);
  }
  if (target.hasScheme || target.hasAuthority) {
    return (null, null);
  }
  final anchor = target.fragment.isEmpty
      ? null
      : Uri.decodeComponent(target.fragment);
  return (Uri.decodeComponent(target.path), anchor);
}

/// [text] with its white space one space, and none at either end.
String _collapsed(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The namespace of EPUB's own attributes, such as `epub:type`.
const _opsNamespace = 'http://www.idpf.org/2007/ops';

/// Whether [node] puts anything on the page: not HTML's white space, a comment, or an empty
/// element such as the page marker `<a id="page12"/>`.
bool _shows(XmlNode node) => switch (node) {
  XmlText() => node.value.replaceAll(_whiteSpace, '').isNotEmpty,
  XmlElement() => node.children.isNotEmpty || node.localName == 'img',
  XmlCDATA() => true,
  _ => false,
};

/// HTML's white space; a no-break space is text.
final _whiteSpace = RegExp(r'[ \t\n\r\f]');

/// Elements that only group blocks, opened up into the blocks inside them.
const _wrappers = {
  'article',
  'aside',
  'div',
  'footer',
  'header',
  'main',
  'nav',
  'section',
};

/// Elements that are one block each.
const _blockElements = {
  'address',
  'blockquote',
  'center',
  'details',
  'dl',
  'figure',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'hgroup',
  'hr',
  'ol',
  'p',
  'pre',
  'table',
  'ul',
};

/// HTML's elements that never hold content: `<br></br>` would be read as two line breaks.
const _voidElements = {
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'source',
  'track',
  'wbr',
};

Uint8List? _bytesAt(Archive archive, String path) {
  final entry = archive.find(path);
  if (entry == null || !entry.isFile) {
    return null;
  }
  // Into a stream of its own: decompressing in place keeps the bytes in the archive for as long
  // as the book is open, every photo of a cookbook included.
  final output = OutputMemoryStream();
  entry.decompress(output);
  return output.getBytes();
}

XmlDocument _xmlAt(Archive archive, String path) {
  final bytes =
      _bytesAt(archive, path) ??
      (throw FormatException('The book has no $path.'));
  return XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
}

/// Where the package file is, as `META-INF/container.xml` names it.
String _packagePath(XmlDocument container) {
  final rootfiles = container.findAllElements('rootfile', namespaceUri: '*');
  final path = rootfiles.isEmpty
      ? null
      : rootfiles.first.getAttribute('full-path');
  if (path == null || path.isEmpty) {
    throw const FormatException('The container names no package file.');
  }
  return path;
}

/// The archive paths of the spine's chapters, in order; those it marks `linear="no"` stand
/// outside the reading order and are left out.
List<String> _readingOrder(String packagePath, XmlDocument package) {
  final hrefs = {
    for (final item in package.findAllElements('item', namespaceUri: '*'))
      ?item.getAttribute('id'): item.getAttribute('href'),
  };
  final base = Uri(path: packagePath);
  final chapters = [
    for (final itemref in package.findAllElements('itemref', namespaceUri: '*'))
      if (itemref.getAttribute('linear') != 'no')
        if (hrefs[itemref.getAttribute('idref')] case final href?)
          Uri.decodeComponent(base.resolve(href).path),
  ];
  if (chapters.isEmpty) {
    throw const FormatException('The package file names no chapters.');
  }
  return chapters;
}

/// Whether the spine runs the pages right to left: `page-progression-direction="rtl"`.
bool _isRightToLeft(XmlDocument package) => package
    .findAllElements('spine', namespaceUri: '*')
    .any(
      (spine) =>
          spine.getAttribute('page-progression-direction')?.trim() == 'rtl',
    );

/// Whether the package file declares the book `pre-paginated`, the EPUB term for fixed pages.
bool _isFixedLayout(XmlDocument package) => package
    .findAllElements('meta', namespaceUri: '*')
    .any(
      (meta) =>
          meta.getAttribute('property') == 'rendition:layout' &&
          meta.innerText.trim() == 'pre-paginated',
    );
