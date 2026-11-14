import 'package:bookserver/app.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });

  testWidgets('shows the app name from the built-in English', (tester) async {
    await tester.pumpWidget(BookserverApp(catalog: english));

    expect(find.text(english.text('app.name')), findsOneWidget);
  });

  testWidgets('takes its title from the catalog', (tester) async {
    await tester.pumpWidget(BookserverApp(catalog: english));

    expect(
      tester.widget<Title>(find.byType(Title)).title,
      english.text('app.name'),
    );
  });

  testWidgets('follows the platform into dark mode', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(BookserverApp(catalog: english));

    final screen = tester.element(find.text(english.text('app.name')));
    expect(Theme.of(screen).brightness, Brightness.dark);
  });
}
