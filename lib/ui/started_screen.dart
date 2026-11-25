import 'package:bookserver/data/account_controller.dart';
import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/i18n/catalog_controller.dart';
import 'package:bookserver/ui/books_screen.dart';
import 'package:bookserver/ui/cover.dart';
import 'package:bookserver/ui/cover_grid.dart';
import 'package:bookserver/ui/list_screen.dart';
import 'package:bookserver/ui/mark_read_menu.dart';
import 'package:bookserver/ui/readers/open_book.dart';
import 'package:bookserver/ui/user_menu.dart';
import 'package:material_ui/material_ui.dart';

/// The books the user started and hasn't finished, the most recently read first, each with its
/// series' name under it: a tap reads on, a long press marks it read or unread.
class StartedScreen extends StatefulWidget {
  const StartedScreen({
    super.key,
    required this.session,
    required this.catalogs,
    required this.account,
  });

  final SessionController session;
  final CatalogController catalogs;
  final AccountController account;

  @override
  State<StartedScreen> createState() => _StartedScreenState();
}

class _StartedScreenState extends State<StartedScreen> {
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
      title: context.t('home.continue_reading'),
      emptyKey: 'home.continue_empty',
      reloadKey: 'home.reload',
      reloadOn: _reloads,
      load: () => session.authorized(
        (api, sessionToken) => BrowseApi(api).startedBooks(sessionToken),
      ),
      actions: [
        UserMenu(
          session: session,
          catalogs: widget.catalogs,
          account: widget.account,
        ),
      ],
      builder: (context, books) => CoverGrid(
        itemCount: books.length,
        withDetail: true,
        itemBuilder: (context, index) {
          final book = books[index];
          // The grid builds every card in its own context: the menu needs the card's.
          return Builder(
            builder: (cardContext) => CoverCard(
              cover: Cover(session: session, kind: CoverKind.book, id: book.id),
              name: bookName(context, book),
              detail: book.seriesName,
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
