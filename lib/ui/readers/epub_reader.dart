import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/epub_book.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/epub_image.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/notice.dart';
import 'package:bookserver/ui/readers/fixed_layout_page.dart';
import 'package:bookserver/ui/readers/page_turner.dart';
import 'package:bookserver/ui/readers/reader_frame.dart';
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
  final _frame = GlobalKey<ReaderFrameState>();
  File? _file;
  EpubBook? _epub;
  List<_Block> _blocks = const [];
  FixedLayoutBook? _fixedLayout;
  String? _errorKey;
  double? _received;

  /// The fixed-layout page on screen.
  var _page = 0;

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
      if (epub.isFixedLayout) {
        final fixedLayout = FixedLayoutBook(epub, widget.book.id);
        // The first page right away, while "Opening the book…" still shows.
        await fixedLayout.prepare(0);
        if (!mounted) {
          epub.close();
          return;
        }
        setState(() {
          _epub = epub;
          _fixedLayout = fixedLayout;
        });
        return;
      }
      final blocks = [
        for (var chapter = 0; chapter < epub.chapters.length; chapter++)
          for (final (index, html) in epub.chapterBlocks(chapter).indexed)
            (
              chapter: chapter,
              html: html,
              startsChapter: index == 0,
              textLength: _textOf(html).length,
            ),
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

  void _toggleBar() => _frame.currentState?.toggleBar();

  @override
  Widget build(BuildContext context) {
    final epub = _epub;
    return ReaderFrame(
      key: _frame,
      title: widget.book.title,
      status: epub == null || _fixedLayout == null || _errorKey != null
          ? null
          : Text(
              context.t('reader.page_of', {
                'page': _page + 1,
                'count': epub.chapters.length,
              }),
            ),
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
    if (_fixedLayout case final fixedLayout?) {
      return PageTurner(
        count: epub.chapters.length,
        onPageChanged: (index) => setState(() => _page = index),
        onTap: _toggleBar,
        pageBuilder: (context, index, decodeWidth) => FixedLayoutPage(
          key: ValueKey(index),
          book: fixedLayout,
          index: index,
          decodeWidth: decodeWidth,
        ),
      );
    }
    return GestureDetector(
      onTap: _toggleBar,
      child: _Blocks(book: epub, blocks: _blocks),
    );
  }
}

/// A block of a chapter — a paragraph, a heading, a list — as HTML, and how many characters of
/// text it holds.
typedef _Block = ({
  int chapter,
  String html,
  bool startsChapter,
  int textLength,
});

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
    return LayoutBuilder(
      builder: (context, constraints) => ListView.custom(
        // One item per block, each built in the frame it appears: an item that grows once it's
        // placed above the screen pushes down the text being read.
        childrenDelegate: _BlockDelegate(
          (context, index) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Widths.reading),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  Spacing.large,
                  _gapAbove(index, textStyle),
                  Spacing.large,
                  _gapBelow(index),
                ),
                child: HtmlWidget(
                  blocks[index].html,
                  buildAsync: false,
                  baseUrl: Uri(
                    scheme: _scheme,
                    path: '/${book.chapters[blocks[index].chapter]}',
                  ),
                  factoryBuilder: () => _BookPictures(book, imageWidth),
                  textStyle: textStyle,
                ),
              ),
            ),
          ),
          childCount: blocks.length,
          heightsAfter: _heightsAfter(
            context,
            textStyle,
            math.min(constraints.maxWidth, Widths.reading) - 2 * Spacing.large,
          ),
        ),
      ),
    );
  }

  double _gapAbove(int index, TextStyle textStyle) => index == 0
      ? Spacing.large
      : blocks[index].startsChapter
      ? Spacing.large * 2
      // HtmlWidget leaves out the margins at its edges; 1 em is the gap it puts between two
      // paragraphs.
      : textStyle.fontSize!;

  double _gapBelow(int index) => index == blocks.length - 1 ? Spacing.large : 0;

  /// For each block, a guess at how tall the blocks after it are: so many lines each, with as
  /// many characters to a line as the book's own text makes when wrapped to [textWidth] in
  /// [textStyle] — lines break between words, so none is filled to the end.
  List<double> _heightsAfter(
    BuildContext context,
    TextStyle textStyle,
    double textWidth,
  ) {
    final sample = [for (final block in blocks.take(100)) _textOf(block.html)]
        .join(' ')
        .trim();
    final text = sample.isEmpty
        ? ' '
        : sample.substring(0, math.min(sample.length, 2000));
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: textWidth);
    final sampleLines = painter.computeLineMetrics().length;
    final perLine = text.length / sampleLines;
    final lineHeight = painter.height / sampleLines;
    painter.dispose();

    final heights = List<double>.filled(blocks.length, 0);
    var below = 0.0;
    for (var index = blocks.length - 1; index >= 0; index--) {
      heights[index] = below;
      final lines = math.max(1, (blocks[index].textLength / perLine).ceil());
      below +=
          _gapAbove(index, textStyle) + lines * lineHeight + _gapBelow(index);
    }
    return heights;
  }
}

/// Builds a book's blocks, and gives the list the book's length from their text: Flutter's own
/// guess averages the blocks built so far, which swings between a heading and a long paragraph.
class _BlockDelegate extends SliverChildBuilderDelegate {
  _BlockDelegate(
    super.builder, {
    required int super.childCount,
    required this.heightsAfter,
  });

  /// For each block, how tall the blocks after it are guessed to be.
  final List<double> heightsAfter;

  @override
  double estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) => trailingScrollOffset + heightsAfter[lastIndex];
}

/// A block's text, its tags left out and its white space one space.
String _textOf(String html) =>
    html.replaceAll(_tag, '').replaceAll(_whiteSpace, ' ');

final _tag = RegExp('<[^>]*>');
final _whiteSpace = RegExp(r'\s+');

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
