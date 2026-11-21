import 'package:bookserver/data/account_controller.dart';
import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/i18n/catalog_controller.dart';
import 'package:bookserver/ui/series_screen.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

/// The libraries by name, [current] marked. Choosing another shows its series in place of the
/// current library's screens, so Back still leads to the library grid.
class LibrarySidebar extends StatelessWidget {
  const LibrarySidebar({
    super.key,
    required this.session,
    required this.catalogs,
    required this.account,
    required this.libraries,
    required this.current,
  });

  final SessionController session;
  final CatalogController catalogs;
  final AccountController account;
  final List<Library> libraries;
  final Library current;

  @override
  Widget build(BuildContext context) {
    // Over the content, the list hides the top bar's button that opened it.
    final overContent = Scaffold.maybeOf(context)?.hasDrawer ?? false;
    return SafeArea(
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: Spacing.medium,
              end: Spacing.small,
            ),
            child: SizedBox(
              height: kToolbarHeight,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.t('menu.libraries'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (overContent)
                    CloseButton(
                      onPressed: () => Scaffold.of(context).closeDrawer(),
                    ),
                ],
              ),
            ),
          ),
          for (final library in libraries)
            ListTile(
              title: Text(library.name),
              selected: library.id == current.id,
              onTap: () => _choose(context, library),
            ),
        ],
      ),
    );
  }

  void _choose(BuildContext context, Library library) {
    if (library.id == current.id) {
      Scaffold.maybeOf(context)?.closeDrawer();
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => SeriesScreen(
          session: session,
          catalogs: catalogs,
          account: account,
          library: library,
          libraries: libraries,
        ),
      ),
      (route) => route.isFirst,
    );
  }
}
