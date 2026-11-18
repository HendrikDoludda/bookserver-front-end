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

  /// The file at [path] in the archive, or null when the book has none there.
  Uint8List? read(String path) => _bytesAt(_archive, path);

  /// What is inside chapter [index]'s `<body>`, as HTML.
  String chapterBody(int index) {
    final text = utf8.decode(read(chapters[index])!, allowMalformed: true);
    return html.parse(text).body?.innerHtml ?? '';
  }

  /// Lets go of the file; nothing can be read after.
  void close() => _input.closeSync();
}

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

/// Whether the package file declares the book `pre-paginated`, the EPUB term for fixed pages.
bool _isFixedLayout(XmlDocument package) => package
    .findAllElements('meta', namespaceUri: '*')
    .any(
      (meta) =>
          meta.getAttribute('property') == 'rendition:layout' &&
          meta.innerText.trim() == 'pre-paginated',
    );
