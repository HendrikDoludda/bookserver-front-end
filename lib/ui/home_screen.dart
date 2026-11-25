import 'package:bookserver/data/account_controller.dart';
import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/i18n/catalog_controller.dart';
import 'package:bookserver/ui/cover.dart';
import 'package:bookserver/ui/cover_grid.dart';
import 'package:bookserver/ui/list_screen.dart';
import 'package:bookserver/ui/series_screen.dart';
import 'package:bookserver/ui/started_screen.dart';
import 'package:bookserver/ui/user_menu.dart';
import 'package:material_ui/material_ui.dart';

/// The first screen once signed in: the server's libraries, each showing how much of it the user
/// has read, and the way to the books they are in the middle of.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.session,
    required this.catalogs,
    required this.account,
  });

  final SessionController session;
  final CatalogController catalogs;
  final AccountController account;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Loads the libraries again, keeping them on screen: this screen is on top again.
  final _reloads = ValueNotifier(0);

  /// Whether a screen lies over this one.
  var _covered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Whichever screen closed last: the sidebar's switch to another library replaces the screen
    // opened from here, so waiting for that one to close would reload too early.
    final onTop = ModalRoute.isCurrentOf(context) ?? true;
    if (onTop && _covered) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _reloads.value++;
        }
      });
    }
    _covered = !onTop;
  }

  @override
  void dispose() {
    _reloads.dispose();
    super.dispose();
  }

  void _open(Widget screen) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return ListScreen<Library>(
      title: context.t('home.title'),
      emptyKey: 'home.empty',
      reloadKey: 'home.reload',
      reloadOn: _reloads,
      load: () => session.authorized(
        (api, sessionToken) => BrowseApi(api).libraries(sessionToken),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.auto_stories),
          tooltip: context.t('home.continue_reading'),
          onPressed: () => _open(
            StartedScreen(
              session: session,
              catalogs: widget.catalogs,
              account: widget.account,
            ),
          ),
        ),
        UserMenu(
          session: session,
          catalogs: widget.catalogs,
          account: widget.account,
        ),
      ],
      builder: (context, libraries) => CoverGrid(
        itemCount: libraries.length,
        withDetail: true,
        itemBuilder: (context, index) {
          final library = libraries[index];
          final read = finishedShare(library.finishedCount, library.bookCount);
          return CoverCard(
            cover: Cover(
              session: session,
              kind: CoverKind.library,
              id: library.id,
            ),
            name: library.name,
            detail: context.plural('browse.series_count', library.seriesCount),
            progress: read.progress,
            finished: read.finished,
            onTap: () => _open(
              SeriesScreen(
                session: session,
                catalogs: widget.catalogs,
                account: widget.account,
                library: library,
                libraries: libraries,
              ),
            ),
          );
        },
      ),
    );
  }
}
