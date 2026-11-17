import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/home_screen.dart';
import 'package:bookserver/ui/login_screen.dart';
import 'package:bookserver/ui/server_screen.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

/// The root: the catalog and the theme above every screen, and the screen for the session's
/// stage, with nothing pushed on top of it once the session has ended.
class BookserverApp extends StatefulWidget {
  const BookserverApp({
    super.key,
    required this.catalog,
    required this.session,
  });

  final Catalog catalog;
  final SessionController session;

  @override
  State<BookserverApp> createState() => _BookserverAppState();
}

class _BookserverAppState extends State<BookserverApp> {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_closeScreensAfterSession);
  }

  @override
  void dispose() {
    widget.session.removeListener(_closeScreensAfterSession);
    super.dispose();
  }

  void _closeScreensAfterSession() {
    if (widget.session.stage is! LoggedIn) {
      _navigator.currentState?.popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CatalogScope(
      catalog: widget.catalog,
      child: MaterialApp(
        navigatorKey: _navigator,
        onGenerateTitle: (context) => context.t('app.name'),
        theme: lightTheme,
        darkTheme: darkTheme,
        home: ListenableBuilder(
          listenable: widget.session,
          builder: (context, _) => switch (widget.session.stage) {
            NeedsServer() => ServerScreen(session: widget.session),
            LoggedOut(:final server, :final endedKey) => LoginScreen(
              session: widget.session,
              server: server,
              endedKey: endedKey,
            ),
            LoggedIn() => HomeScreen(session: widget.session),
          },
        ),
      ),
    );
  }
}
