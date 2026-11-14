import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

/// The root: the catalog and the theme above every screen.
class BookserverApp extends StatelessWidget {
  const BookserverApp({super.key, required this.catalog});

  final Catalog catalog;

  @override
  Widget build(BuildContext context) {
    return CatalogScope(
      catalog: catalog,
      child: MaterialApp(
        onGenerateTitle: (context) => context.t('app.name'),
        theme: lightTheme,
        darkTheme: darkTheme,
        home: const _Placeholder(),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.large),
          child: Text(
            context.t('app.name'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
      ),
    );
  }
}
