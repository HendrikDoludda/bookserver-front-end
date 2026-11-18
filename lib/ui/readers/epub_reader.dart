import 'dart:async';
import 'dart:io';

import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/epub_book.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/epub_image.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/notice.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

/// Reads an EPUB: downloads it through the session, then shows its chapters one after the other.
class EpubReader extends StatefulWidget {
  const EpubReader({super.key, required this.session, required this.book});

  final SessionController session;
  final Book book;

  @override
  State<EpubReader> createState() => _EpubReaderState();
}

class _EpubReaderState extends State<EpubReader> {
  File? _file;
  EpubBook? _epub;
  List<_Block> _blocks = const [];
  String? _errorKey;
  double? _received;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _epub?.close();
    if (_file case final file?) {
      unawaited(_delete(file));
    }
    super.dispose();
  }

  void _retry() {
    setState(() {
      _errorKey = null;
      _received = null;
    });
    _open();
  }

  Future<void> _open() async {
    try {
      final file = _file ??= await _freshFile(widget.book.id);
      await widget.session.authorized(
        (api, sessionToken) => api.download(
          bookFilePath(widget.book.id),
          file,
          bearer: sessionToken,
          onProgress: _showProgress,
        ),
      );
      if (!mounted) {
        await _delete(file);
        return;
      }
      final EpubBook epub;
      try {
        epub = EpubBook.open(file);
      } on FormatException {
        setState(() => _errorKey = 'reader.open_failed');
        return;
      }
      final blocks = [
        for (var chapter = 0; chapter < epub.chapters.length; chapter++)
          for (final (index, html) in epub.chapterBlocks(chapter).indexed)
            (chapter: chapter, html: html, startsChapter: index == 0),
      ];
      setState(() {
        _epub = epub;
        _blocks = blocks;
      });
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _errorKey = errorTextKey(error, CatalogScope.of(context)),
        );
      }
    }
  }

  void _showProgress(int received, int? total) {
    if (mounted && total != null && total > 0) {
      setState(() => _received = received / total);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.book.title)),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_errorKey case final errorKey?) {
      return Notice(
        text: context.t(errorKey),
        color: Theme.of(context).colorScheme.error,
        action: FilledButton.tonal(
          onPressed: _retry,
          child: Text(context.t('reader.retry')),
        ),
      );
    }
    final epub = _epub;
    if (epub == null) {
      return Notice(
        text: context.t('reader.opening'),
        action: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Widths.form),
          child: LinearProgressIndicator(value: _received),
        ),
      );
    }
    return _Blocks(book: epub, blocks: _blocks);
  }
}

/// A block of a chapter — a paragraph, a heading, a list — as HTML.
typedef _Block = ({int chapter, String html, bool startsChapter});

/// A book's blocks, chapter after chapter, in a column that keeps lines easy to follow.
class _Blocks extends StatelessWidget {
  const _Blocks({required this.book, required this.blocks});

  final EpubBook book;
  final List<_Block> blocks;

  @override
  Widget build(BuildContext context) {
    final imageWidth = (Widths.reading * MediaQuery.devicePixelRatioOf(context))
        .round();
    final textStyle = Theme.of(context).textTheme.bodyLarge!;
    // One item per block, each built in the frame it appears: an item that grows once it's
    // placed above the screen pushes down the text being read.
    return ListView.builder(
      itemCount: blocks.length,
      itemBuilder: (context, index) {
        final block = blocks[index];
        final gapAbove = index == 0
            ? Spacing.large
            : block.startsChapter
            ? Spacing.large * 2
            // HtmlWidget leaves out the margins at its edges; 1 em is the gap it puts between
            // two paragraphs.
            : textStyle.fontSize!;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Widths.reading),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                Spacing.large,
                gapAbove,
                Spacing.large,
                index == blocks.length - 1 ? Spacing.large : 0,
              ),
              child: HtmlWidget(
                block.html,
                buildAsync: false,
                baseUrl: Uri(
                  scheme: _scheme,
                  path: '/${book.chapters[block.chapter]}',
                ),
                factoryBuilder: () => _BookPictures(book, imageWidth),
                textStyle: textStyle,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Gives an `<img>` its picture from the book's own archive, and any other picture none.
class _BookPictures extends WidgetFactory {
  _BookPictures(this._book, this._width);

  final EpubBook _book;
  final int _width;

  @override
  ImageProvider? imageProviderFromNetwork(String url) {
    final uri = Uri.tryParse(url);
    // A picture from anywhere else would make the app load it from the internet.
    if (uri == null || uri.scheme != _scheme || uri.hasAuthority) {
      return null;
    }
    return ResizeImage(
      EpubImage(_book, Uri.decodeComponent(uri.path.substring(1))),
      width: _width,
      allowUpscaling: false,
    );
  }
}

/// The scheme of a chapter's base address, which turns a relative `src` into a path in the book.
const _scheme = 'epub';

Future<File> _freshFile(int bookId) async {
  final folder = await getTemporaryDirectory();
  // A name of its own per opening: a reader of the same book closing just now deletes only its file.
  return File(
    '${folder.path}${Platform.pathSeparator}'
    'book-$bookId-${DateTime.now().microsecondsSinceEpoch}.epub',
  );
}

Future<void> _delete(File file) async {
  try {
    await file.delete();
  } on FileSystemException {
    // It was never written, or is gone already.
  }
}
