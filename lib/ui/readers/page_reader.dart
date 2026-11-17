import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/list_screen.dart';
import 'package:bookserver/ui/notice.dart';
import 'package:bookserver/ui/server_image.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Reads a CBZ or image-folder book one page at a time: swiped, or turned with the arrow keys,
/// and zoomable.
class PageReader extends StatelessWidget {
  const PageReader({super.key, required this.session, required this.book});

  final SessionController session;
  final Book book;

  @override
  Widget build(BuildContext context) {
    return ListScreen<int>(
      title: book.title,
      emptyKey: 'reader.open_failed',
      reloadKey: 'reader.retry',
      reloadInAppBar: false,
      load: () => session.authorized(
        (api, sessionToken) => BrowseApi(api).pagesOf(book.id, sessionToken),
      ),
      builder: (context, numbers) =>
          _Pages(session: session, bookId: book.id, numbers: numbers),
    );
  }
}

class _Pages extends StatefulWidget {
  const _Pages({
    required this.session,
    required this.bookId,
    required this.numbers,
  });

  final SessionController session;
  final int bookId;
  final List<int> numbers;

  @override
  State<_Pages> createState() => _PagesState();
}

class _PagesState extends State<_Pages> {
  final _pages = PageController();

  // One zoom for every page: turning the page resets it, and while a page is zoomed no swipe
  // reaches the pages beside it.
  final _zoom = TransformationController();

  var _index = 0;
  var _zoomed = false;

  // Sharp up to a 2× zoom, where a full-size scan would decode to about 100 MB. Fixed while the
  // book is open, so resizing the window or turning the phone doesn't fetch every page again.
  late final int _decodeWidth =
      (MediaQuery.sizeOf(context).shortestSide *
              MediaQuery.devicePixelRatioOf(context) *
              2)
          .round();

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_zoomChanged);
  }

  @override
  void dispose() {
    _pages.dispose();
    _zoom.dispose();
    super.dispose();
  }

  void _zoomChanged() {
    // A pinch back to full size can leave the scale a rounding error above 1.
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) {
      setState(() => _zoomed = zoomed);
    }
  }

  void _turn(int by) {
    final target = _index + by;
    if (target < 0 || target >= widget.numbers.length) {
      return;
    }
    _zoom.value = Matrix4.identity();
    _pages.animateToPage(
      target,
      duration: Durations.medium2,
      curve: Easing.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                  _turn(-1),
              const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                  _turn(1),
            },
            child: Focus(
              autofocus: true,
              child: PageView.builder(
                controller: _pages,
                // Builds the page on either side as well, so the next one is loaded before it's
                // turned to.
                allowImplicitScrolling: true,
                physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
                itemCount: widget.numbers.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) => InteractiveViewer(
                  transformationController: _zoom,
                  minScale: 1,
                  child: _Page(
                    image: ResizeImage(
                      ServerImage(
                        widget.session,
                        pagePath(widget.bookId, widget.numbers[index]),
                      ),
                      width: _decodeWidth,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.small),
            child: Text(
              context.t('reader.page_of', {
                'page': _index + 1,
                'count': widget.numbers.length,
              }),
            ),
          ),
        ),
      ],
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
