import 'package:bookserver/app.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/data/session_store.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/i18n/catalog_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  // Reading an asset or secure storage before runApp needs the binding runApp would set up.
  WidgetsFlutterBinding.ensureInitialized();
  final english = await Catalog.loadBuiltInEnglish();
  final client = http.Client();
  final session = SessionController(
    store: SecureSessionStore(),
    client: client,
  );
  await session.load();
  final catalogs = CatalogController(
    builtIn: english,
    client: client,
    session: session,
  );
  catalogs.load();
  runApp(BookserverApp(catalogs: catalogs, session: session));
}
