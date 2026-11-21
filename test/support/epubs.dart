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
/// order) in its spine, declaring the book's pages fixed when [fixedLayout] is true, and the
/// spine's `page-progression-direction` [pageProgression] unless it's null. An item named in
/// [properties] carries them, such as `nav` for the navigation file; [toc] is the spine's `toc`,
/// the id of the NCX.
String packageXml(
  Map<String, String> items,
  List<String> spine, {
  bool fixedLayout = false,
  String? pageProgression,
  Map<String, String> properties = const {},
  String? toc,
}) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata>
    ${fixedLayout ? '<meta property="rendition:layout">pre-paginated</meta>' : ''}
  </metadata>
  <manifest>
${[for (final MapEntry(key: id, value: href) in items.entries) '    <item id="$id" href="$href" media-type="application/xhtml+xml"${properties[id] == null ? '' : ' properties="${properties[id]}"'}/>'].join('\n')}
  </manifest>
  <spine${pageProgression == null ? '' : ' page-progression-direction="$pageProgression"'}${toc == null ? '' : ' toc="$toc"'}>
${[for (final idref in spine) '    <itemref idref="$idref"/>'].join('\n')}
  </spine>
</package>''';

/// An EPUB 3 navigation file whose `<nav epub:type="toc">` holds [list], an `<ol>`.
String navXhtml(String list) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>Contents</title></head>
<body>
  <nav epub:type="landmarks"><ol><li><a href="text/one.xhtml">Not the contents</a></li></ol></nav>
  <nav epub:type="toc" id="toc"><h1>Contents</h1>$list</nav>
</body>
</html>''';

/// An EPUB 2 NCX whose `navMap` holds [points], its `navPoint`s.
String ncxXml(String points) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head><meta name="dtb:uid" content="id"/></head>
  <docTitle><text>Not an entry</text></docTitle>
  <navMap>$points</navMap>
</ncx>''';

/// A chapter file whose `<body>` holds [body].
String chapterXhtml(String body) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Not part of the text</title><link rel="stylesheet" href="style.css"/></head>
<body>$body</body>
</html>''';

/// A fixed-layout page whose `<body>` holds [body], linking [stylesheets], with a viewport meta of
/// [viewport] unless it's null.
String fixedPageXhtml(
  String body, {
  String? viewport = 'width=1000, height=1500',
  List<String> stylesheets = const ['style.css'],
}) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Not part of the text</title>
${[for (final sheet in stylesheets) '<link type="text/css" rel="stylesheet" href="$sheet"/>'].join('\n')}
${viewport == null ? '' : '<meta content="$viewport" name="viewport"/>'}
</head>
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
