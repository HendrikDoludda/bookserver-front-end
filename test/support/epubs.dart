import 'dart:io';

import 'package:archive/archive.dart';

/// A `META-INF/container.xml` naming the package file at [packagePath].
String containerXml([String packagePath = 'OEBPS/content.opf']) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="$packagePath" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';

/// A package file listing [items] (id → href) in its manifest and [spine] (idrefs, in reading
/// order) in its spine, declaring the book's pages fixed when [fixedLayout] is true.
String packageXml(
  Map<String, String> items,
  List<String> spine, {
  bool fixedLayout = false,
}) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata>
    ${fixedLayout ? '<meta property="rendition:layout">pre-paginated</meta>' : ''}
  </metadata>
  <manifest>
${[for (final MapEntry(key: id, value: href) in items.entries) '    <item id="$id" href="$href" media-type="application/xhtml+xml"/>'].join('\n')}
  </manifest>
  <spine>
${[for (final idref in spine) '    <itemref idref="$idref"/>'].join('\n')}
  </spine>
</package>''';

/// A chapter file whose `<body>` holds [body].
String chapterXhtml(String body) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Not part of the text</title><link rel="stylesheet" href="style.css"/></head>
<body>$body</body>
</html>''';

/// The bytes of an EPUB, a zip archive, holding [files] (path → text or bytes).
List<int> epubBytes(Map<String, Object> files) {
  final archive = Archive();
  for (final MapEntry(key: path, value: content) in files.entries) {
    archive.addFile(switch (content) {
      String text => ArchiveFile.string(path, text),
      List<int> bytes => ArchiveFile.bytes(path, bytes),
      _ => throw ArgumentError.value(content, path),
    });
  }
  return ZipEncoder().encode(archive);
}

/// Writes [files] as an EPUB into [folder] and answers the file.
File writeEpub(Directory folder, Map<String, Object> files) =>
    File('${folder.path}/book.epub')..writeAsBytesSync(epubBytes(files));
