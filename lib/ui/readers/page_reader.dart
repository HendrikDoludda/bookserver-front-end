import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/list_screen.dart';
import 'package:bookserver/ui/notice.dart';
import 'package:bookserver/ui/readers/page_turner.dart';
import 'package:bookserver/ui/server_image.dart';
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
      builder: (context, numbers) => PageTurner(
        count: numbers.length,
        pageBuilder: (context, index, decodeWidth) => _Page(
          image: ResizeImage(
            ServerImage(session, pagePath(book.id, numbers[index])),
            width: decodeWidth,
          ),
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
