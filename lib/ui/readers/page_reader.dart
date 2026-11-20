import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/notice.dart';
import 'package:bookserver/ui/readers/page_turner.dart';
import 'package:bookserver/ui/readers/reader_frame.dart';
import 'package:bookserver/ui/server_image.dart';
import 'package:material_ui/material_ui.dart';

/// Reads a CBZ or image-folder book one page at a time: swiped, or turned with the arrow keys,
/// and zoomable.
class PageReader extends StatefulWidget {
  const PageReader({super.key, required this.session, required this.book});

  final SessionController session;
  final Book book;

  @override
  State<PageReader> createState() => _PageReaderState();
}

class _PageReaderState extends State<PageReader> {
  final _frame = GlobalKey<ReaderFrameState>();
  List<int>? _numbers;
  String? _errorKey;
  var _index = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _retry() {
    setState(() => _errorKey = null);
    _load();
  }

  Future<void> _load() async {
    try {
      final numbers = await widget.session.authorized(
        (api, sessionToken) =>
            BrowseApi(api).pagesOf(widget.book.id, sessionToken),
      );
      if (mounted) {
        setState(() => _numbers = numbers);
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _errorKey = errorTextKey(error, CatalogScope.of(context)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final numbers = _numbers;
    return ReaderFrame(
      key: _frame,
      title: widget.book.title,
      status: numbers == null || numbers.isEmpty
          ? null
          : Text(
              context.t('reader.page_of', {
                'page': _index + 1,
                'count': numbers.length,
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
    final numbers = _numbers;
    if (numbers == null) {
      return Notice(
        text: context.t('reader.opening'),
        action: const CircularProgressIndicator(),
      );
    }
    if (numbers.isEmpty) {
      return Notice(text: context.t('reader.open_failed'));
    }
    return PageTurner(
      count: numbers.length,
      onPageChanged: (index) => setState(() => _index = index),
      onTap: () => _frame.currentState?.toggleBar(),
      pageBuilder: (context, index, decodeWidth) => _Page(
        image: ResizeImage(
          ServerImage(widget.session, pagePath(widget.book.id, numbers[index])),
          width: decodeWidth,
        ),
      ),
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
