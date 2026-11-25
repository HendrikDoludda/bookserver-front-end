import 'package:bookserver/data/account_controller.dart';
import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/i18n/catalog_controller.dart';
import 'package:bookserver/ui/cover.dart';
import 'package:bookserver/ui/cover_grid.dart';
import 'package:bookserver/ui/library_sidebar.dart';
import 'package:bookserver/ui/list_screen.dart';
import 'package:bookserver/ui/mark_read_menu.dart';
import 'package:bookserver/ui/readers/open_book.dart';
import 'package:bookserver/ui/user_menu.dart';
import 'package:material_ui/material_ui.dart';

/// A series' books, in reading order, with the [libraries] to switch to beside them. Each shows
/// how far the user has read it; a long press marks it read or unread.
class BooksScreen extends StatefulWidget {
  const BooksScreen({
    super.key,
    required this.session,
    required this.catalogs,
    required this.account,
    required this.library,
    required this.libraries,
    required this.series,
  });

  final SessionController session;
  final CatalogController catalogs;
  final AccountController account;

  /// The library the series was opened from.
  final Library library;

  /// Every library, as the library grid loaded them.
  final List<Library> libraries;
  final Series series;

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  /// Loads the books again, keeping them on screen: a reader closed, or a book was marked.
  final _reloads = ValueNotifier(0);

  @override
  void dispose() {
    _reloads.dispose();
    super.dispose();
  }

  void _reload() {
    if (mounted) {
      _reloads.value++;
    }
  }

  Future<void> _read(Book book) async {
    await openBook(context, widget.session, book);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return ListScreen<Book>(
      title: widget.series.name,
      emptyKey: 'browse.books_empty',
      reloadKey: 'browse.reload',
      reloadOn: _reloads,
      load: () => session.authorized(
        (api, sessionToken) =>
            BrowseApi(api).booksOf(widget.series.id, sessionToken),
      ),
      actions: [
        UserMenu(
          session: session,
          catalogs: widget.catalogs,
          account: widget.account,
        ),
      ],
      sidebar: LibrarySidebar(
        session: session,
        catalogs: widget.catalogs,
        account: widget.account,
        libraries: widget.libraries,
        current: widget.library,
      ),
      builder: (context, books) => CoverGrid(
        itemCount: books.length,
        itemBuilder: (context, index) {
          final book = books[index];
          // The grid builds every card in its own context: the menu needs the card's.
          return Builder(
            builder: (cardContext) => CoverCard(
              cover: Cover(session: session, kind: CoverKind.book, id: book.id),
              name: bookName(context, book),
              progress: readShare(book.progress),
              finished: book.progress.finished,
              onTap: () => _read(book),
              onLongPress: () =>
                  offerMark(cardContext, session, book, onMarked: _reload),
            ),
          );
        },
      ),
    );
  }
}

/// How far into a book its [progress] lies, from 0 to 1, counting the place on screen as read;
/// null for a book finished or never opened.
double? readShare(Progress progress) => switch (progress) {
  Progress(finished: true) => null,
  Progress(place: (:final position, :final total)) => (position + 1) / total,
  _ => null,
};

/// A book's name within its series: its volume and chapter, or its title when it has neither.
String bookName(BuildContext context, Book book) =>
    switch ((book.volume, book.chapter)) {
      (final volume?, final chapter?) => context.t('browse.volume_chapter', {
        'volume': context.number(volume),
        'chapter': context.number(chapter),
      }),
      (final volume?, null) => context.t('browse.volume', {
        'number': context.number(volume),
      }),
      (null, final chapter?) => context.t('browse.chapter', {
        'number': context.number(chapter),
      }),
      (null, null) => book.title,
    };
