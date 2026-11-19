import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/i18n/catalog_controller.dart';
import 'package:bookserver/ui/home_screen.dart';
import 'package:bookserver/ui/login_screen.dart';
import 'package:bookserver/ui/server_screen.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

/// The root: the catalog [catalogs] holds and the theme above every screen, and the screen for
/// the session's stage, with nothing pushed on top of it once the session has ended.
class BookserverApp extends StatefulWidget {
  const BookserverApp({
    super.key,
    required this.catalogs,
    required this.session,
  });

  final CatalogController catalogs;
  final SessionController session;

  @override
  State<BookserverApp> createState() => _BookserverAppState();
}

class _BookserverAppState extends State<BookserverApp> {
  final _navigator = GlobalKey<NavigatorState>();

  late Type _stageKind;

  @override
  void initState() {
    super.initState();
    _stageKind = widget.session.stage.runtimeType;
    widget.session.addListener(_closeScreensOnNewStage);
  }

  @override
  void dispose() {
    widget.session.removeListener(_closeScreensOnNewStage);
    super.dispose();
  }

  /// Leaves only the first screen, the new stage's, when the stage changes kind: a screen pushed
  /// for the stage before, such as the code step over the login screen, belongs to it.
  void _closeScreensOnNewStage() {
    final kind = widget.session.stage.runtimeType;
    if (kind != _stageKind) {
      _stageKind = kind;
      _navigator.currentState?.popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.catalogs,
      builder: (context, _) {
        final catalog = widget.catalogs.catalog;
        final materialLocale = materialLocaleOf(catalog.language);
        return CatalogScope(
          catalog: catalog,
          child: MaterialApp(
            navigatorKey: _navigator,
            locale: materialLocale,
            supportedLocales: [materialLocale],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            onGenerateTitle: (context) => context.t('app.name'),
            theme: lightTheme,
            darkTheme: darkTheme,
            home: ListenableBuilder(
              listenable: widget.session,
              builder: (context, _) => switch (widget.session.stage) {
                NeedsServer() => ServerScreen(session: widget.session),
                LoggedOut(:final server, :final endedKey) => LoginScreen(
                  session: widget.session,
                  catalogs: widget.catalogs,
                  server: server,
                  endedKey: endedKey,
                ),
                LoggedIn() => HomeScreen(session: widget.session),
              },
            ),
          ),
        );
      },
    );
  }
}

/// The locale Material's own texts — the Back tooltip, the Cut/Copy/Paste menu — use for the
/// catalog's [language]: its own where `material_ui` has texts for it, else English.
// A locale no delegate supports would leave the app without MaterialLocalizations, which every
// Back button needs.
Locale materialLocaleOf(String language) {
  final parts = language.split('-');
  final locale = Locale(parts.first, parts.length > 1 ? parts[1] : null);
  final supported = GlobalMaterialLocalizations.delegates.every(
    (delegate) => delegate.isSupported(locale),
  );
  return supported ? locale : const Locale('en');
}
