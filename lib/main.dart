import 'package:bookserver/app.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/data/session_store.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  // Reading an asset or secure storage before runApp needs the binding runApp would set up.
  WidgetsFlutterBinding.ensureInitialized();
  final catalog = await Catalog.loadBuiltInEnglish();
  final session = SessionController(
    store: SecureSessionStore(),
    client: http.Client(),
  );
  await session.load();
  runApp(BookserverApp(catalog: catalog, session: session));
}
