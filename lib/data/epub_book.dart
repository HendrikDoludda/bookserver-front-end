import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';

/// An EPUB file opened for reading: its chapters in reading order, and any file in it, read from
/// the archive only when asked for.
class EpubBook {
  EpubBook._(
    this._input,
    this._archive,
    this.chapters, {
    required this.isFixedLayout,
    required this.isRightToLeft,
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

  /// The file at [path] in the archive, or null when the book has none there.
  Uint8List? read(String path) => _bytesAt(_archive, path);

  /// What chapter [index]'s `<body>` holds, as blocks of HTML in reading order — paragraphs,
  /// headings, lists — each inside the tags of the elements that wrap it, so their styles still
  /// apply.
  List<String> chapterBlocks(int index) {
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
      final body = html.parse(text).body?.innerHtml.trim() ?? '';
      return body.isEmpty ? const [] : [body];
    }
    final body = document.rootElement.childElements
        .where((element) => element.localName == 'body')
        .firstOrNull;
    if (body == null) {
      return const [];
    }
    // Written for an HTML parser to read again, which ignores `/>` on an element that can hold
    // content.
    for (final element in body.descendantElements) {
      element.isSelfClosing = _voidElements.contains(element.localName);
    }
    final blocks = <String>[];
    _addBlocks(body, '', '', blocks);
    return blocks;
  }

  /// Lets go of the file; nothing can be read after.
  void close() => _input.closeSync();
}

/// Adds what [parent] holds to [blocks], each block written between [opening] and [closing], the
/// tags of the elements around it. A wrapper such as `<section>` is opened up into the blocks
/// inside it; loose text and inline elements between blocks become a block of their own.
void _addBlocks(
  XmlElement parent,
  String opening,
  String closing,
  List<String> blocks,
) {
  final loose = <XmlNode>[];
  void addLoose() {
    if (loose.any(_shows)) {
      blocks.add(
        '$opening${loose.map((node) => node.toXmlString()).join()}$closing',
      );
    }
    loose.clear();
  }

  for (final node in parent.children) {
    if (node is XmlElement && _wrappers.contains(node.localName)) {
      addLoose();
      final attributes = node.attributes
          .map((attribute) => ' $attribute')
          .join();
      final name = node.name.qualified;
      _addBlocks(
        node,
        '$opening<$name$attributes>',
        '</$name>$closing',
        blocks,
      );
    } else if (node is XmlElement && _blockElements.contains(node.localName)) {
      addLoose();
      blocks.add('$opening${node.toXmlString()}$closing');
    } else {
      loose.add(node);
    }
  }
  addLoose();
}

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
