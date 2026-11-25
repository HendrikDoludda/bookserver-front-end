import 'package:bookserver/data/account_controller.dart';
import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/i18n/catalog_controller.dart';
import 'package:bookserver/ui/books_screen.dart';
import 'package:bookserver/ui/cover.dart';
import 'package:bookserver/ui/cover_grid.dart';
import 'package:bookserver/ui/library_sidebar.dart';
import 'package:bookserver/ui/list_screen.dart';
import 'package:bookserver/ui/user_menu.dart';
import 'package:material_ui/material_ui.dart';

/// A library's series, by name, with the [libraries] to switch to beside them. Each shows how
/// many of its books the user has read.
class SeriesScreen extends StatefulWidget {
  const SeriesScreen({
    super.key,
    required this.session,
    required this.catalogs,
    required this.account,
    required this.library,
    required this.libraries,
  });

  final SessionController session;
  final CatalogController catalogs;
  final AccountController account;
  final Library library;

  /// Every library, as the library grid loaded them.
  final List<Library> libraries;

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  /// Loads the series again, keeping them on screen: a series' books were open.
  final _reloads = ValueNotifier(0);

  @override
  void dispose() {
    _reloads.dispose();
    super.dispose();
  }

  Future<void> _open(Series series) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BooksScreen(
          session: widget.session,
          catalogs: widget.catalogs,
          account: widget.account,
          library: widget.library,
          libraries: widget.libraries,
          series: series,
        ),
      ),
    );
    if (mounted) {
      _reloads.value++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return ListScreen<Series>(
      title: widget.library.name,
      emptyKey: 'browse.series_empty',
      reloadKey: 'browse.reload',
      reloadOn: _reloads,
      load: () => session.authorized(
        (api, sessionToken) =>
            BrowseApi(api).seriesOf(widget.library.id, sessionToken),
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
      builder: (context, series) => CoverGrid(
        itemCount: series.length,
        withDetail: true,
        itemBuilder: (context, index) {
          final one = series[index];
          final read = finishedShare(one.finishedCount, one.bookCount);
          return CoverCard(
            cover: Cover(session: session, kind: CoverKind.series, id: one.id),
            name: one.name,
            detail: context.plural('browse.book_count', one.bookCount),
            progress: read.progress,
            finished: read.finished,
            onTap: () => _open(one),
          );
        },
      ),
    );
  }
}
