import 'dart:async';
import 'dart:io';

import 'package:bookserver/data/api_client.dart';
import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/data/session_http_client.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/notice.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

/// Reads a PDF with pdfrx, which fetches only the parts of the file it shows, in byte ranges
/// through the session.
class PdfReader extends StatefulWidget {
  const PdfReader({super.key, required this.session, required this.book});

  final SessionController session;
  final Book book;

  @override
  State<PdfReader> createState() => _PdfReaderState();
}

class _PdfReaderState extends State<PdfReader> {
  PdfDocumentRefDirect? _document;
  String? _errorKey;
  int? _page;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
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
      final document = await PdfDocument.openUri(
        server.resolve(bookFilePath(widget.book.id)),
        preferRangeAccess: true,
        // Otherwise opening measures every page, which in a scan means fetching most of the file.
        useProgressiveLoading: true,
        timeout: ApiClient.defaultTimeout,
      );
      if (!mounted) {
        await _close(document);
        return;
      }
      setState(
        () => _document = PdfDocumentRefDirect(document, autoDispose: false),
      );
    } on Exception {
      // pdfrx wraps every cause, a lost connection as much as a damaged file.
      if (mounted) {
        setState(() => _errorKey = 'reader.open_failed');
      }
    }
  }

  void _pageChanged(int? page) => setState(() => _page = page);

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
    final document = _document;
    if (document == null) {
      return Notice(
        text: context.t('reader.opening'),
        action: const CircularProgressIndicator(),
      );
    }
    return Column(
      children: [
        Expanded(
          child: PdfViewer(
            document,
            params: pdfViewerParams(
              background: Theme.of(context).colorScheme.surfaceContainerHighest,
              onPageChanged: _pageChanged,
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.small),
            child: Text(
              context.t('reader.page_of', {
                'page': _page ?? 1,
                'count': document.document.pages.length,
              }),
            ),
          ),
        ),
      ],
    );
  }
}

/// The settings of the viewer a PDF is read in.
PdfViewerParams pdfViewerParams({
  required Color background,
  required PdfPageChangedCallback onPageChanged,
}) => PdfViewerParams(
  backgroundColor: background,
  // Renders, and so downloads, the pages up to three window heights ahead, about two scanned
  // pages, so they have arrived before they scroll in.
  verticalCacheExtent: 0.5,
  pageDropShadow: null, //added this
  onePassRenderingSizeThreshold: 2000, //added this
  behaviorControlParams: const PdfViewerBehaviorControlParams(
    // Measures a page once it is about to show, not every page at open, which in a scan would
    // fetch most of the file.
    loadPageDimensionsOnDemand: true,
    //enableLowResolutionPagePreview: false,
    // A page shown larger than 2000 pixels also gets a full-resolution image of what is on screen.
    // Waiting until scrolling has paused for 300 ms keeps that render and its GPU upload off every
    // scroll step.
    partialImageLoadingDelay: Duration(milliseconds: 300),
  ),
  onPageChanged: onPageChanged,
);

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
