import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/i18n/catalog_controller.dart';
import 'package:bookserver/ui/books_screen.dart';
import 'package:bookserver/ui/cover.dart';
import 'package:bookserver/ui/cover_grid.dart';
import 'package:bookserver/ui/list_screen.dart';
import 'package:bookserver/ui/user_menu.dart';
import 'package:material_ui/material_ui.dart';

/// A library's series, by name.
class SeriesScreen extends StatelessWidget {
  const SeriesScreen({
    super.key,
    required this.session,
    required this.catalogs,
    required this.library,
  });

  final SessionController session;
  final CatalogController catalogs;
  final Library library;

  @override
  Widget build(BuildContext context) {
    return ListScreen<Series>(
      title: library.name,
      emptyKey: 'browse.series_empty',
      reloadKey: 'browse.reload',
      load: () => session.authorized(
        (api, sessionToken) =>
            BrowseApi(api).seriesOf(library.id, sessionToken),
      ),
      actions: [UserMenu(session: session, catalogs: catalogs)],
      builder: (context, series) => CoverGrid(
        itemCount: series.length,
        withDetail: true,
        itemBuilder: (context, index) {
          final one = series[index];
          return CoverCard(
            cover: Cover(session: session, kind: CoverKind.series, id: one.id),
            name: one.name,
            detail: context.plural('browse.book_count', one.bookCount),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BooksScreen(
                  session: session,
                  catalogs: catalogs,
                  series: one,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
