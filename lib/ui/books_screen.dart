import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/i18n/catalog_controller.dart';
import 'package:bookserver/ui/cover.dart';
import 'package:bookserver/ui/cover_grid.dart';
import 'package:bookserver/ui/list_screen.dart';
import 'package:bookserver/ui/readers/open_book.dart';
import 'package:bookserver/ui/user_menu.dart';
import 'package:material_ui/material_ui.dart';

/// A series' books, in reading order.
class BooksScreen extends StatelessWidget {
  const BooksScreen({
    super.key,
    required this.session,
    required this.catalogs,
    required this.series,
  });

  final SessionController session;
  final CatalogController catalogs;
  final Series series;

  @override
  Widget build(BuildContext context) {
    return ListScreen<Book>(
      title: series.name,
      emptyKey: 'browse.books_empty',
      reloadKey: 'browse.reload',
      load: () => session.authorized(
        (api, sessionToken) => BrowseApi(api).booksOf(series.id, sessionToken),
      ),
      actions: [UserMenu(session: session, catalogs: catalogs)],
      builder: (context, books) => CoverGrid(
        itemCount: books.length,
        itemBuilder: (context, index) {
          final book = books[index];
          return CoverCard(
            cover: Cover(session: session, kind: CoverKind.book, id: book.id),
            name: _nameOf(context, book),
            onTap: () => openBook(context, session, book),
          );
        },
      ),
    );
  }
}

/// A book's name within its series: its volume and chapter, or its title when it has neither.
String _nameOf(BuildContext context, Book book) => switch ((
  book.volume,
  book.chapter,
)) {
  (final volume?, final chapter?) => context.t('browse.volume_chapter', {
    'volume': volume,
    'chapter': chapter,
  }),
  (final volume?, null) => context.t('browse.volume', {'number': volume}),
  (null, final chapter?) => context.t('browse.chapter', {'number': chapter}),
  (null, null) => book.title,
};
