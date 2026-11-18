import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/cover.dart';
import 'package:bookserver/ui/cover_grid.dart';
import 'package:bookserver/ui/list_screen.dart';
import 'package:bookserver/ui/series_screen.dart';
import 'package:material_ui/material_ui.dart';

/// The first screen once signed in: the server's libraries.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return ListScreen<Library>(
      title: context.t('home.title'),
      emptyKey: 'home.empty',
      reloadKey: 'home.reload',
      load: () => session.authorized(
        (api, sessionToken) => BrowseApi(api).libraries(sessionToken),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: context.t('home.sign_out'),
          onPressed: session.logOut,
        ),
      ],
      builder: (context, libraries) => CoverGrid(
        itemCount: libraries.length,
        withDetail: true,
        itemBuilder: (context, index) {
          final library = libraries[index];
          return CoverCard(
            cover: Cover(
              session: session,
              kind: CoverKind.library,
              id: library.id,
            ),
            name: library.name,
            detail: context.plural('browse.series_count', library.seriesCount),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    SeriesScreen(session: session, library: library),
              ),
            ),
          );
        },
      ),
    );
  }
}
