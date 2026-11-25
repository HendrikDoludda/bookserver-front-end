import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/epub_book.dart';
import 'package:bookserver/data/preferences.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/epub_image.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/notice.dart';
import 'package:bookserver/ui/preferences_scope.dart';
import 'package:bookserver/ui/readers/anchored_list.dart';
import 'package:bookserver/ui/readers/contents_list.dart';
import 'package:bookserver/ui/readers/fixed_layout_page.dart';
import 'package:bookserver/ui/readers/page_turner.dart';
import 'package:bookserver/ui/readers/progress_saver.dart';
import 'package:bookserver/ui/readers/reader_frame.dart';
import 'package:bookserver/ui/readers/zoom.dart';
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
  final _turner = GlobalKey<PageTurnerState>();
  final _list = GlobalKey<AnchoredListState>();
  File? _file;
  EpubBook? _epub;
  List<_Block> _blocks = const [];

  /// For each chapter of a flowing book, the index of its first block, and the block each anchor
  /// in it lands on, counted from that first block.
  List<int> _chapterStarts = const [];
  List<Map<String, int>> _anchors = const [];

  FixedLayoutBook? _fixedLayout;
  String? _errorKey;
  double? _received;

  /// The fixed-layout page on screen.
  var _page = 0;

  /// The block a flowing book opens at.
  var _openingBlock = 0;
  ProgressSaver? _saver;

  /// The zoom step fixed-layout pages show at while the book is open, and whether a pinch has
  /// left it.
  var _zoom = ZoomStep.fitPage;
  var _pinched = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _saver?.close();
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
    // Asked while the file downloads.
    final asking = _progress();
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
      final progress = await asking;
      if (epub.isFixedLayout) {
        final fixedLayout = FixedLayoutBook(epub, widget.book.id);
        final count = epub.chapters.length;
        final opening = progress.openAt(count);
        // The opening page right away, while "Opening the book…" still shows.
        await fixedLayout.prepare(opening);
        if (!mounted) {
          epub.close();
          return;
        }
        setState(() {
          _epub = epub;
          _fixedLayout = fixedLayout;
          _page = opening;
        });
        _startSaving(progress, opening, count);
        if (count > 0 && opening == count - 1) {
          _saver?.ended(opening, count);
        }
        return;
      }
      final blocks = <_Block>[];
      final chapterStarts = <int>[];
      final anchors = <Map<String, int>>[];
      for (var chapter = 0; chapter < epub.chapters.length; chapter++) {
        final made = epub.chapter(chapter);
        chapterStarts.add(blocks.length);
        anchors.add(made.anchors);
        for (final (index, html) in made.blocks.indexed) {
          blocks.add((
            chapter: chapter,
            html: html,
            startsChapter: index == 0,
            textLength: _textOf(html).length,
          ));
        }
      }
      final opening = progress.openAt(blocks.length);
      setState(() {
        _epub = epub;
        _blocks = blocks;
        _chapterStarts = chapterStarts;
        _anchors = anchors;
        _openingBlock = opening;
      });
      _startSaving(progress, opening, blocks.length);
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _errorKey = errorTextKey(error, CatalogScope.of(context)),
        );
      }
    }
  }

  /// The signed-in user's progress in the book; none when it can't be had, which opens the book at
  /// its start.
  Future<Progress> _progress() async {
    try {
      final details = await widget.session.authorized(
        (api, sessionToken) =>
            BrowseApi(api).book(widget.book.id, sessionToken),
      );
      return details.progress;
    } on Exception {
      return Progress.none;
    }
  }

  /// Saves the place from now on, the book having opened at [opening] of [count].
  void _startSaving(Progress progress, int opening, int count) {
    if (count < 1) {
      return;
    }
    _saver?.close();
    _saver = ProgressSaver(
      session: widget.session,
      bookId: widget.book.id,
      opening: (position: opening, total: count),
      restarting: progress.finished,
    );
  }

  /// Saves where a flowing book rests: the block at the top, and its end once nothing is left
  /// below.
  void _scrolled(ScrollMetrics metrics) =>
      _saveTop(atEnd: metrics.extentAfter < 1);

  /// Saves the block at the top, [atEnd] as the book's end, once the coming frame is laid out: a
  /// scroll ends, and a jump is asked for, before the blocks have moved.
  void _saveTop({bool atEnd = false}) {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        final top = mounted ? _list.currentState?.topItem : null;
        if (top == null) {
          return;
        }
        if (atEnd) {
          _saver?.ended(top, _blocks.length);
        } else {
          _saver?.moved(top, _blocks.length);
        }
      })
      ..scheduleFrame();
  }

  void _showProgress(int received, int? total) {
    if (mounted && total != null && total > 0) {
      setState(() => _received = received / total);
    }
  }

  void _toggleBar() => _frame.currentState?.toggleBar();

  void _setZoom(ZoomStep step) {
    setState(() {
      _zoom = step;
      _pinched = false;
    });
    _turner.currentState?.zoomTo(step);
  }

  /// Goes to [anchor] in [file], the place a contents entry or a link names: in a flowing book the
  /// block it lands on, else the file's first block, at the top of the screen; in a fixed-layout
  /// book the page made from [file].
  void _goTo(String file, String? anchor) {
    final chapter = _epub?.chapters.indexOf(file) ?? -1;
    if (chapter < 0) {
      return;
    }
    if (_fixedLayout != null) {
      _turner.currentState?.turnTo(chapter);
      return;
    }
    final inChapter = anchor == null ? null : _anchors[chapter][anchor];
    _list.currentState?.showItem(
      math.min(_chapterStarts[chapter] + (inChapter ?? 0), _blocks.length - 1),
    );
    _saveTop();
  }

  /// Follows a link in a flowing book's text, written as [url]: to its place when that is in the
  /// book. Taken either way: a link out of the book opens nothing.
  bool _follow(String url) {
    final link = Uri.tryParse(url);
    if (link != null &&
        link.scheme == _scheme &&
        !link.hasAuthority &&
        link.path.startsWith('/')) {
      _goTo(
        Uri.decodeComponent(link.path.substring(1)),
        link.fragment.isEmpty ? null : Uri.decodeComponent(link.fragment),
      );
    }
    return true;
  }

  /// The book's contents, each entry going to its place; an entry whose file isn't in the reading
  /// order goes nowhere.
  List<ContentsRow> _contents(EpubBook epub) => contentsRows(
    epub.toc,
    titleOf: (entry) => entry.title,
    childrenOf: (entry) => entry.children,
    goOf: (entry) => switch (entry.file) {
      final file? when epub.chapters.contains(file) => () => _goTo(
        file,
        entry.anchor,
      ),
      _ => null,
    },
  );

  /// Makes a flowing book's text [by] percent larger, the block at the top staying there.
  void _changeFont(PreferencesController preferences, int by) {
    // Taken while the screen still shows the text at its old size.
    final top = _list.currentState?.topItem;
    unawaited(
      preferences.setFontPercent(preferences.preferences.fontPercent + by),
    );
    if (top != null) {
      _list.currentState?.showItem(top);
      _saveTop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final epub = _epub;
    final preferences = PreferencesScope.of(context);
    final fontPercent = preferences.preferences.fontPercent;
    final flowing = epub != null && _fixedLayout == null && _errorKey == null;
    final contents = epub == null || _errorKey != null
        ? const <ContentsRow>[]
        : _contents(epub);
    return ReaderFrame(
      key: _frame,
      title: widget.book.title,
      controls: [
        if (contents.isNotEmpty) ContentsButton(rows: contents),
        if (_fixedLayout != null && _errorKey == null)
          ZoomButton(step: _pinched ? null : _zoom, onChanged: _setZoom),
        if (flowing)
          _FontSize(
            percent: fontPercent,
            onSmaller: fontPercent > Preferences.smallestFont
                ? () => _changeFont(preferences, -Preferences.fontStep)
                : null,
            onLarger: fontPercent < Preferences.largestFont
                ? () => _changeFont(preferences, Preferences.fontStep)
                : null,
          ),
      ],
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
        key: _turner,
        count: epub.chapters.length,
        initialIndex: _page,
        rightToLeft: epub.isRightToLeft,
        initialZoom: _zoom,
        // A page not parsed yet takes the first page's size, as nearly every book's pages share
        // one.
        pageShape: (index) =>
            (fixedLayout.prepared(index) ?? fixedLayout.prepared(0))
                ?.size
                .aspectRatio,
        onPageChanged: (index) {
          setState(() {
            _page = index;
            _pinched = false;
          });
          _saver?.pageShown(index, epub.chapters.length);
        },
        onPinch: () => setState(() => _pinched = true),
        onTap: _toggleBar,
        pageBuilder: (context, index, decodeWidth) => FixedLayoutPage(
          key: ValueKey(index),
          book: fixedLayout,
          index: index,
          decodeWidth: decodeWidth,
        ),
      );
    }
    return NotificationListener<ScrollEndNotification>(
      onNotification: (notification) {
        // Only the list's own scrolling: a wide table in a block scrolls on its own.
        if (notification.depth == 0) {
          _scrolled(notification.metrics);
        }
        return false;
      },
      child: GestureDetector(
        onTap: _toggleBar,
        child: _Blocks(
          listKey: _list,
          book: epub,
          blocks: _blocks,
          initialBlock: _openingBlock,
          fontPercent: PreferencesScope.of(context).preferences.fontPercent,
          onLink: _follow,
        ),
      ),
    );
  }
}

/// The flowing reader's text size control: smaller, the size in percent, larger. A button without
/// its callback is off, as at the smallest and the largest size.
class _FontSize extends StatelessWidget {
  const _FontSize({
    required this.percent,
    required this.onSmaller,
    required this.onLarger,
  });

  final int percent;
  final VoidCallback? onSmaller;
  final VoidCallback? onLarger;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.text_decrease),
          tooltip: context.t('reader.font_smaller'),
          onPressed: onSmaller,
        ),
        Text(context.t('reader.percent', {'percent': percent})),
        IconButton(
          icon: const Icon(Icons.text_increase),
          tooltip: context.t('reader.font_larger'),
          onPressed: onLarger,
        ),
      ],
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

/// A book's blocks, chapter after chapter, in a column that keeps lines easy to follow, their text
/// at [fontPercent] of its normal size; [initialBlock] at the top when it opens.
class _Blocks extends StatelessWidget {
  const _Blocks({
    required this.listKey,
    required this.book,
    required this.blocks,
    required this.initialBlock,
    required this.fontPercent,
    required this.onLink,
  });

  final GlobalKey<AnchoredListState> listKey;
  final EpubBook book;
  final List<_Block> blocks;
  final int initialBlock;
  final int fontPercent;

  /// Called with a link's address, resolved against its chapter, when it's tapped.
  final bool Function(String url) onLink;

  @override
  Widget build(BuildContext context) {
    final imageWidth = (Widths.reading * MediaQuery.devicePixelRatioOf(context))
        .round();
    final normal = Theme.of(context).textTheme.bodyLarge!;
    // The blocks, the gaps between them and the guess at their heights all go by this style.
    final textStyle = normal.copyWith(
      fontSize: normal.fontSize! * fontPercent / 100,
    );
    return LayoutBuilder(
      builder: (context, constraints) => AnchoredList(
        key: listKey,
        count: blocks.length,
        initialItem: initialBlock,
        guessedHeights: _guessedHeights(
          context,
          textStyle,
          math.min(constraints.maxWidth, Widths.reading) - 2 * Spacing.large,
        ),
        // One item per block, each built in the frame it appears: an item that grows once it's
        // placed above the screen pushes down the text being read.
        itemBuilder: (context, index) => Center(
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
                onTapUrl: onLink,
                textStyle: textStyle,
              ),
            ),
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

  /// For each block, a guess at how tall it is: so many lines, with as many characters to a line
  /// as the book's own text makes when wrapped to [textWidth] in [textStyle] — lines break between
  /// words, so none is filled to the end.
  List<double> _guessedHeights(
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

    return [
      for (var index = 0; index < blocks.length; index++)
        _gapAbove(index, textStyle) +
            math.max(1, (blocks[index].textLength / perLine).ceil()) *
                lineHeight +
            _gapBelow(index),
    ];
  }
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
