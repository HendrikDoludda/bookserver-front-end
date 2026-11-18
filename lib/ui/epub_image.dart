import 'dart:ui' as ui;

import 'package:bookserver/data/epub_book.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// A picture inside an EPUB, read from the book's archive when the image cache asks for it.
@immutable
class EpubImage extends ImageProvider<EpubImage> {
  const EpubImage(this.book, this.path);

  final EpubBook book;

  /// The picture's path in the archive, such as `OEBPS/images/dish.jpg`.
  final String path;

  @override
  Future<EpubImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(EpubImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: _load(decode),
        scale: 1,
        debugLabel: path,
      );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes =
        book.read(path) ?? (throw FormatException('The book has no $path.'));
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is EpubImage && identical(other.book, book) && other.path == path;

  @override
  int get hashCode => Object.hash(identityHashCode(book), path);
}
