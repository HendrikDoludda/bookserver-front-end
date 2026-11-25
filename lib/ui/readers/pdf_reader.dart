import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:bookserver/data/api_client.dart';
import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/data/session_http_client.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/notice.dart';
import 'package:bookserver/ui/readers/contents_list.dart';
import 'package:bookserver/ui/readers/progress_saver.dart';
import 'package:bookserver/ui/readers/reader_frame.dart';
import 'package:bookserver/ui/readers/reading_mode_button.dart';
import 'package:bookserver/ui/readers/tap_zones.dart';
import 'package:bookserver/ui/readers/zoom.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

/// Reads a PDF with pdfrx, which fetches only the parts of the file it shows, in byte ranges
/// through the session: in one column scrolled top to bottom, or one page at a time from left to
/// right or right to left, as the user's mode says.
class PdfReader extends StatefulWidget {
  const PdfReader({super.key, required this.session, required this.book});

  final SessionController session;
  final Book book;

  @override
  State<PdfReader> createState() => _PdfReaderState();
}

class _PdfReaderState extends State<PdfReader> {
  final _frame = GlobalKey<ReaderFrameState>();
  PdfDocumentRefDirect? _document;
  int? _seriesId;
  var _mode = ReadingMode.continuous;

  // One for each viewer: a viewer that closes detaches its controller, after the next one has
  // attached.
  var _viewer = PdfViewerController();

  String? _errorKey;
  int? _page;

  /// The page the viewer opens at, counted from 1, as pdfrx counts: the saved one.
  var _openAt = 1;
  ProgressSaver? _saver;

  /// The PDF's own contents, once read; none while it hasn't any.
  List<PdfOutlineNode> _outline = const [];

  /// The zoom step on screen; null before one is chosen in continuous scroll, and after a pinch.
  ZoomStep? _zoom;

  /// The step chosen in the dropdown, until a pinch leaves it: another mode's viewer opens at it.
  ZoomStep? _chosenZoom;

  /// The zoom when a drag or a pinch started, to tell them apart when it ends.
  var _zoomAtStart = 1.0;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _saver?.close();
    unawaited(_close(_document?.document));
    super.dispose();
  }

  void _retry() {
    setState(() => _errorKey = null);
    _open();
  }

  Future<void> _open() async {
    try {
      await pdfrxFlutterInitialize();
      final server = switch (widget.session.stage) {
        LoggedIn(:final server) => server,
        _ => throw const SessionEndedException(),
      };
      _deleteBlockCache();
      // pdfrx takes the client for every download from this static hook.
      Pdfrx.createHttpClient = () => SessionHttpClient(widget.session);
      final opening = PdfDocument.openUri(
        server.resolve(bookFilePath(widget.book.id)),
        preferRangeAccess: true,
        // Otherwise opening measures every page, which in a scan means fetching most of the file.
        useProgressiveLoading: true,
        timeout: ApiClient.defaultTimeout,
      );
      final asking = widget.session.authorized(
        (api, sessionToken) =>
            BrowseApi(api).book(widget.book.id, sessionToken),
      );
      try {
        // Either failure shows at once; Future.wait handles the other one's as well.
        await Future.wait([opening, asking], eagerError: true);
      } on Exception {
        // The document is no use without its mode: it is closed once it has opened.
        unawaited(opening.then(_close, onError: (Object _) {}));
        rethrow;
      }
      final document = await opening;
      final details = await asking;
      if (!mounted) {
        await _close(document);
        return;
      }
      final count = document.pages.length;
      final startAt = details.progress.openAt(count);
      setState(() {
        _document = PdfDocumentRefDirect(document, autoDispose: false);
        _seriesId = details.seriesId;
        _mode = details.mode ?? ReadingMode.continuous;
        _zoom = _startZoom(_mode);
        _openAt = startAt + 1;
      });
      if (count > 0) {
        final saver = _saver = ProgressSaver(
          session: widget.session,
          bookId: widget.book.id,
          opening: (position: startAt, total: count),
          restarting: details.progress.finished,
        );
        // A book whose last page shows as it opens is at its end already.
        if (startAt == count - 1) {
          saver.ended(startAt, count);
        }
      }
      unawaited(_loadOutline(document));
    } on Exception {
      // pdfrx wraps every cause, a lost connection as much as a damaged file.
      if (mounted) {
        setState(() => _errorKey = 'reader.open_failed');
      }
    }
  }

  /// Reads the PDF's outline, its own contents, once it is open.
  Future<void> _loadOutline(PdfDocument document) async {
    try {
      final outline = await document.loadOutline();
      if (mounted && identical(_document?.document, document)) {
        setState(() => _outline = outline);
      }
    } on Exception {
      // A PDF whose outline can't be read shows no contents; it reads as before.
    }
  }

  void _goToDest(PdfDest dest) {
    if (_viewer.isReady) {
      unawaited(_viewer.goToDest(dest));
    }
  }

  void _pageChanged(int? page) {
    // The viewer names its first page once it has laid the pages out; only a later change is a
    // turn.
    final turned = _page != null && page != _page;
    setState(() => _page = page);
    if (turned) {
      _hideBar();
    }
    final count = _document?.document.pages.length ?? 0;
    if (page != null && count > 0) {
      _saver?.pageShown(page - 1, count);
    }
  }

  void _hideBar() => _frame.currentState?.hideBar();

  void _toggleBar() => _frame.currentState?.toggleBar();

  /// Shows [mode] in a new viewer, which opens at the page on screen: at the step chosen, else at
  /// that mode's own start.
  void _setMode(ReadingMode mode) {
    if (mode == _mode) {
      return;
    }
    setState(() {
      _mode = mode;
      _viewer = PdfViewerController();
      _zoom = _chosenZoom ?? _startZoom(mode);
    });
  }

  void _viewerReady() {
    if (_chosenZoom case final step?) {
      _setZoom(step);
    }
  }

  /// The step a viewer in [mode] opens at: a paged mode fits the page; continuous scroll opens as
  /// pdfrx lays it out, at no step.
  static ZoomStep? _startZoom(ReadingMode mode) =>
      mode == ReadingMode.continuous ? null : ZoomStep.fitPage;

  void _interactionStarted() {
    _hideBar();
    if (_viewer.isReady) {
      _zoomAtStart = _viewer.currentZoom;
    }
  }

  void _interactionEnded() {
    if (_viewer.isReady &&
        (_viewer.currentZoom / _zoomAtStart - 1).abs() > 0.01) {
      setState(() => _zoom = _chosenZoom = null);
    }
  }

  /// Shows the page on screen at [step]: fitted whole or to its width, or a multiple of fitted
  /// whole around the middle of the view.
  void _setZoom(ZoomStep step) {
    final viewer = _viewer;
    final page = viewer.isReady ? viewer.pageNumber : null;
    final fit = page == null ? null : viewer.calcMatrixForFit(pageNumber: page);
    if (page == null || fit == null) {
      return;
    }
    setState(() => _zoom = _chosenZoom = step);
    switch (step) {
      case ZoomStep.fitPage:
        unawaited(viewer.goTo(fit));
      case ZoomStep.fitWidth:
        unawaited(
          viewer.goTo(viewer.calcMatrixFitWidthForPage(pageNumber: page)),
        );
      case ZoomStep.x150 || ZoomStep.x200 || ZoomStep.x300:
        unawaited(
          viewer.setZoom(viewer.centerPosition, fit.zoom * step.times!),
        );
    }
  }

  /// Turns [by] pages in reading order, never past either end.
  void _turn(int by) {
    final viewer = _viewer;
    final page = viewer.isReady ? viewer.pageNumber : null;
    if (page == null) {
      return;
    }
    final target = page + by;
    if (target >= 1 && target <= viewer.pageCount) {
      unawaited(viewer.goToPage(pageNumber: target));
    }
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    final opened = document != null && _errorKey == null;
    return ReaderFrame(
      key: _frame,
      title: widget.book.title,
      controls: [
        if (opened)
          ReadingModeButton(
            session: widget.session,
            seriesId: _seriesId,
            mode: _mode,
            onChanged: _setMode,
          ),
        if (opened && _outline.isNotEmpty)
          ContentsButton(rows: outlineRows(_outline, _goToDest)),
        if (opened) ZoomButton(step: _zoom, onChanged: _setZoom),
      ],
      status: document == null || _errorKey != null
          ? null
          : Text(
              context.t('reader.page_of', {
                'page': _page ?? _openAt,
                'count': document.document.pages.length,
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
    final document = _document;
    if (document == null) {
      return Notice(
        text: context.t('reader.opening'),
        action: const CircularProgressIndicator(),
      );
    }
    return PdfViewer(
      document,
      // A mode is a new layout: its own viewer, opening at the page on screen, finds that page
      // whichever way the pages ran before.
      key: ValueKey(_mode),
      controller: _viewer,
      initialPageNumber: _page ?? _openAt,
      params: pdfViewerParams(
        mode: _mode,
        background: Theme.of(context).colorScheme.surfaceContainerHighest,
        onPageChanged: _pageChanged,
        onTap: _toggleBar,
        onTurn: _turn,
        onInteractionStart: _interactionStarted,
        onInteractionEnd: _interactionEnded,
        onViewerReady: _viewerReady,
        onLink: _goToDest,
      ),
    );
  }
}

/// The settings of the viewer a PDF is read in [mode]: one column scrolled top to bottom, or one
/// page at a time, fitted to the window, from left to right or from right to left.
///
/// [onTap] is called for a single tap on the pages — in a paged mode, one in their middle third;
/// [onTurn] with the pages to turn, forward in reading order, for an arrow key or a tap on an
/// outer third in a paged mode; [onInteractionStart] and [onInteractionEnd] when a drag or a pinch
/// starts and ends; [onViewerReady] once the viewer has laid out its first pages; [onLink] with
/// the place a link to one of the PDF's own pages goes to — a link out of it does nothing.
PdfViewerParams pdfViewerParams({
  required ReadingMode mode,
  required Color background,
  required PdfPageChangedCallback onPageChanged,
  required VoidCallback onTap,
  required ValueChanged<int> onTurn,
  required VoidCallback onInteractionStart,
  required VoidCallback onInteractionEnd,
  required VoidCallback onViewerReady,
  required ValueChanged<PdfDest> onLink,
}) {
  final paged = mode != ReadingMode.continuous;
  final rightToLeft = mode == ReadingMode.rtl;
  // The turn that goes to the right on screen.
  final rightward = rightToLeft ? -1 : 1;
  return PdfViewerParams(
    backgroundColor: background,
    layoutStrategy: switch (mode) {
      ReadingMode.continuous => const SequentialPagesLayout(),
      ReadingMode.ltr => const SequentialPagesLayout(
        scrollDirection: Axis.horizontal,
        fitMode: PdfFitMode.fit,
      ),
      ReadingMode.rtl => const RightToLeftPagesLayout(),
    },
    paging: paged ? const PdfPaging() : null,
    // pdfrx guesses the page on screen from pages that run left to right.
    calculateCurrentPageNumber: rightToLeft ? mostVisiblePage : null,
    // Renders, and so downloads, pages two window heights above and below the screen: three scrolled
    // smoothly on an M2 at full screen, and two pre-renders two window heights less.
    verticalCacheExtent: 2,
    // The keys work as soon as the book opens, as in the comic reader.
    keyHandlerParams: const PdfViewerKeyHandlerParams(autofocus: true),
    behaviorControlParams: const PdfViewerBehaviorControlParams(
      // Measures a page once it is about to show, not every page at open, which in a scan would
      // fetch most of the file.
      loadPageDimensionsOnDemand: true,
      // Waiting until scrolling has paused for 300 ms keeps that render and its GPU upload off every
      // scroll step.
      partialImageLoadingDelay: Duration(milliseconds: 300),
    ),
    onPageChanged: onPageChanged,
    onInteractionStart: (_) => onInteractionStart(),
    onInteractionEnd: (_) => onInteractionEnd(),
    onViewerReady: (document, controller) => onViewerReady(),
    linkHandlerParams: PdfLinkHandlerParams(
      // Only the PDF's own links: text that reads like an address would be a link to nowhere.
      enableAutoLinkDetection: false,
      onLinkTap: (link) {
        if (link.dest case final dest?) {
          onLink(dest);
        }
      },
    ),
    // pdfrx's own arrow keys only nudge a paged view, which then snaps back.
    onKey: paged
        ? (params, key, isRealKeyPress) {
            if (key == LogicalKeyboardKey.arrowRight) {
              onTurn(rightward);
              return true;
            }
            if (key == LogicalKeyboardKey.arrowLeft) {
              onTurn(-rightward);
              return true;
            }
            return null;
          }
        : null,
    onGeneralTap: (context, controller, details) {
      if (details.type != PdfViewerGeneralTapType.tap) {
        return false;
      }
      final width = context.size?.width;
      if (!paged || width == null) {
        onTap();
        return true;
      }
      final dx = details.localPosition.dx;
      switch (tapZoneAt(dx, width, rightToLeft: rightToLeft)) {
        case TapZone.previous:
          onTurn(-1);
        case TapZone.next:
          onTurn(1);
        case TapZone.middle:
          onTap();
      }
      return true;
    },
  );
}

/// The rows of a PDF's [outline], each node going to its place through [go]; a node without one
/// goes nowhere.
List<ContentsRow> outlineRows(
  List<PdfOutlineNode> outline,
  ValueChanged<PdfDest> go,
) => contentsRows(
  outline,
  titleOf: (node) => node.title,
  childrenOf: (node) => node.children,
  goOf: (node) => switch (node.dest) {
    final dest? => () => go(dest),
    null => null,
  },
);

/// One page at a time from right to left, each fitted to the window: page 1 at the right end.
@immutable
class RightToLeftPagesLayout extends PdfPageLayoutStrategy {
  const RightToLeftPagesLayout();

  static const _leftToRight = SequentialPagesLayout(
    scrollDirection: Axis.horizontal,
    fitMode: PdfFitMode.fit,
  );

  @override
  PdfPageLayout resolve(PdfPageLayoutContext context) {
    final mirrored = _leftToRight.resolve(context);
    final width = mirrored.documentSize.width;
    final count = mirrored.pageLayouts.length;
    return _RightToLeftPageLayout(
      pageLayouts: [
        for (final page in mirrored.pageLayouts)
          Rect.fromLTRB(
            width - page.right,
            page.top,
            width - page.left,
            page.bottom,
          ),
      ],
      documentSize: mirrored.documentSize,
      margin: mirrored.margin,
      fitMode: mirrored.fitMode,
      primaryAxis: Axis.horizontal,
      // pdfrx turns to the spread beside the one on screen, so they are listed as they lie, left
      // to right: the last page first.
      spreads: [
        for (var page = count; page >= 1; page--) PdfPageRange.single(page),
      ],
    );
  }

  @override
  bool operator ==(Object other) => other is RightToLeftPagesLayout;

  @override
  int get hashCode => (RightToLeftPagesLayout).hashCode;
}

/// Right-to-left geometry: one page per spread, the spreads from the last page to the first.
class _RightToLeftPageLayout extends PdfPageLayout {
  _RightToLeftPageLayout({
    required super.pageLayouts,
    required super.documentSize,
    super.margin,
    super.fitMode,
    super.primaryAxis,
    super.spreads,
  });

  // pdfrx's own lookup is a binary search that expects the first page first.
  @override
  int spreadIndexOf(int pageNumber) =>
      pageNumber < 1 || pageNumber > pageLayouts.length
      ? -1
      : pageLayouts.length - pageNumber;
}

/// The page that takes up the most of [visibleRect]'s width, or null when none shows.
int? mostVisiblePage(
  Rect visibleRect,
  List<Rect> pageRects,
  PdfViewerController controller,
) {
  int? best;
  var widest = 0.0;
  for (final (index, page) in pageRects.indexed) {
    final shown =
        math.min(page.right, visibleRect.right) -
        math.max(page.left, visibleRect.left);
    if (shown > widest) {
      best = index + 1;
      widest = shown;
    }
  }
  return best;
}

Future<void> _close(PdfDocument? document) async {
  await document?.dispose();
  _deleteBlockCache();
}

/// Deletes the blocks pdfrx has downloaded; nothing else uses its `pdfrx.cache` folder.
void _deleteBlockCache() {
  final root = Pdfrx.cacheDirectoryPath;
  if (root == null) {
    return;
  }
  // Synchronous, though on the UI thread: the folder holds one sparse file per book, which deletes
  // at once.
  try {
    Directory('$root${Platform.pathSeparator}pdfrx.cache')
        .deleteSync(recursive: true);
  } on FileSystemException {
    // There was no cache to delete.
  }
}
