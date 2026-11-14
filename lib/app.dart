import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/home_screen.dart';
import 'package:bookserver/ui/login_screen.dart';
import 'package:bookserver/ui/server_screen.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

/// The root: the catalog and the theme above every screen, and the screen for the session's
/// stage.
class BookserverApp extends StatelessWidget {
  const BookserverApp({
    super.key,
    required this.catalog,
    required this.session,
  });

  final Catalog catalog;
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return CatalogScope(
      catalog: catalog,
      child: MaterialApp(
        onGenerateTitle: (context) => context.t('app.name'),
        theme: lightTheme,
        darkTheme: darkTheme,
        home: ListenableBuilder(
          listenable: session,
          builder: (context, _) => switch (session.stage) {
            NeedsServer() => ServerScreen(session: session),
            LoggedOut(:final server, :final endedKey) => LoginScreen(
              session: session,
              server: server,
              endedKey: endedKey,
            ),
            LoggedIn() => HomeScreen(session: session),
          },
        ),
      ),
    );
  }
}
