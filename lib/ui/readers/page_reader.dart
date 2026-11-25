import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/notice.dart';
import 'package:bookserver/ui/readers/page_column.dart';
import 'package:bookserver/ui/readers/page_turner.dart';
import 'package:bookserver/ui/readers/progress_saver.dart';
import 'package:bookserver/ui/readers/reader_frame.dart';
import 'package:bookserver/ui/readers/reading_mode_button.dart';
import 'package:bookserver/ui/readers/zoom.dart';
import 'package:bookserver/ui/server_image.dart';
import 'package:material_ui/material_ui.dart';

/// Reads a CBZ or image-folder book in the user's mode: one page at a time, right to left or left
/// to right, or top to bottom in one scrolling column.
class PageReader extends StatefulWidget {
  const PageReader({super.key, required this.session, required this.book});

  final SessionController session;
  final Book book;

  @override
  State<PageReader> createState() => _PageReaderState();
}

class _PageReaderState extends State<PageReader> {
  final _frame = GlobalKey<ReaderFrameState>();
  final _turner = GlobalKey<PageTurnerState>();
  List<BookPage>? _pages;
  List<double> _shapes = const [];
  int? _seriesId;
  var _mode = ReadingMode.ltr;
  String? _errorKey;
  var _index = 0;
  ProgressSaver? _saver;

  /// The zoom step the pages show at while the book is open, and whether a pinch has left it.
  var _zoom = ZoomStep.fitPage;
  var _pinched = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saver?.close();
    super.dispose();
  }

  void _retry() {
    setState(() => _errorKey = null);
    _load();
  }

  Future<void> _load() async {
    try {
      final (pages, details) = await widget.session.authorized((
        api,
        sessionToken,
      ) async {
        final browse = BrowseApi(api);
        final pages = browse.pagesOf(widget.book.id, sessionToken);
        final details = browse.book(widget.book.id, sessionToken);
        // Both asked at once. Future.wait answers once both have, with the first failure if any,
        // so a failure of the other is never left unhandled.
        await Future.wait([pages, details]);
        return (await pages, await details);
      });
      if (mounted) {
        final opening = details.progress.openAt(pages.length);
        setState(() {
          _pages = pages;
          _shapes = pageShapes([for (final page in pages) page.size]);
          _seriesId = details.seriesId;
          _mode = details.mode ?? ReadingMode.ltr;
          _index = opening;
        });
        if (pages.isNotEmpty) {
          final saver = _saver = ProgressSaver(
            session: widget.session,
            bookId: widget.book.id,
            opening: (position: opening, total: pages.length),
            restarting: details.progress.finished,
          );
          // A book whose last page shows as it opens is at its end already.
          if (opening == pages.length - 1) {
            saver.ended(opening, pages.length);
          }
        }
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _errorKey = errorTextKey(error, CatalogScope.of(context)),
        );
      }
    }
  }

  void _setZoom(ZoomStep step) {
    setState(() {
      _zoom = step;
      _pinched = false;
    });
    _turner.currentState?.zoomTo(step);
  }

  @override
  Widget build(BuildContext context) {
    final count = _pages?.length ?? 0;
    return ReaderFrame(
      key: _frame,
      title: widget.book.title,
      controls: [
        if (count > 0)
          ReadingModeButton(
            session: widget.session,
            seriesId: _seriesId,
            mode: _mode,
            onChanged: (mode) => setState(() => _mode = mode),
          ),
        if (count > 0 && _mode != ReadingMode.continuous)
          ZoomButton(step: _pinched ? null : _zoom, onChanged: _setZoom),
      ],
      status: count > 0
          ? Text(
              context.t('reader.page_of', {'page': _index + 1, 'count': count}),
            )
          : null,
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
    final pages = _pages;
    if (pages == null) {
      return Notice(
        text: context.t('reader.opening'),
        action: const CircularProgressIndicator(),
      );
    }
    if (pages.isEmpty) {
      return Notice(text: context.t('reader.open_failed'));
    }
    Widget page(BuildContext context, int index, int decodeWidth) => _Page(
      image: ResizeImage(
        ServerImage(
          widget.session,
          pagePath(widget.book.id, pages[index].number),
        ),
        width: decodeWidth,
      ),
    );
    // A turn shows the next page at the zoom step again.
    void pageChanged(int index) {
      setState(() {
        _index = index;
        _pinched = false;
      });
      _saver?.pageShown(index, pages.length);
    }

    void toggleBar() => _frame.currentState?.toggleBar();
    // Either one takes over at the page the other was on.
    if (_mode == ReadingMode.continuous) {
      return PageColumn(
        sizes: [for (final page in pages) page.size],
        initialIndex: _index,
        onPageChanged: pageChanged,
        onTap: toggleBar,
        pageBuilder: page,
      );
    }
    return PageTurner(
      key: _turner,
      count: pages.length,
      initialIndex: _index,
      rightToLeft: _mode == ReadingMode.rtl,
      initialZoom: _zoom,
      pageShape: (index) => _shapes[index],
      onPageChanged: pageChanged,
      onTap: toggleBar,
      onPinch: () => setState(() => _pinched = true),
      pageBuilder: page,
    );
  }
}

/// One page: a spinner while it loads, the page, or why it didn't load with Try again.
class _Page extends StatefulWidget {
  const _Page({required this.image});

  final ImageProvider image;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  // A new Image, under a new key, asks the image cache again; ResizeImage has already taken the
  // failed load out of it.
  var _attempt = 0;

  void _retry() => setState(() => _attempt++);

  @override
  Widget build(BuildContext context) {
    return Image(
      key: ValueKey(_attempt),
      image: widget.image,
      fit: BoxFit.contain,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
          wasSynchronouslyLoaded || frame != null
          ? child
          : const Center(child: CircularProgressIndicator()),
      errorBuilder: (context, error, stackTrace) => Notice(
        text: context.t('reader.page_failed'),
        color: Theme.of(context).colorScheme.error,
        action: FilledButton.tonal(
          onPressed: _retry,
          child: Text(context.t('reader.retry')),
        ),
      ),
    );
  }
}
