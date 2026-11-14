import 'package:bookserver/app.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  // Reading an asset before runApp needs the binding that runApp would otherwise set up.
  WidgetsFlutterBinding.ensureInitialized();
  final catalog = await Catalog.loadBuiltInEnglish();
  runApp(BookserverApp(catalog: catalog));
}
