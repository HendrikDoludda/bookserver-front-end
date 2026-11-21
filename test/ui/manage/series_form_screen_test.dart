import 'package:bookserver/i18n/catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/manage_server.dart';
import '../../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });
  setUp(() => PaintingBinding.instance.imageCache.clear());

  /// Starts the app signed in as an admin and opens [name] from Manage's list of series.
  Future<void> openSeries(
    WidgetTester tester,
    ManageServer server,
    String name,
  ) async {
    await pumpApp(
      tester,
      catalog: english,
      store: signedInStore(),
      server: server.fake,
      followAccount: true,
    );
    await tester.pumpAndSettle();
    await chooseInUserMenu(tester, english, 'menu.manage');
    await tester.pumpAndSettle();
    await tester.tap(find.text(english.text('manage.series')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  Finder field(String labelKey) =>
      find.widgetWithText(TextField, english.text(labelKey));

  Future<void> save(WidgetTester tester) async {
    await tester.tap(
      find.widgetWithText(TextButton, english.text('manage.save')),
    );
    await tester.pumpAndSettle();
  }

  Future<void> deleteConfirmed(WidgetTester tester) async {
    await tester.tap(
      find.widgetWithText(OutlinedButton, english.text('manage.delete')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, english.text('manage.delete')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the list marks a series in no library', (tester) async {
    final server = ManageServer(
      libraries: [libraryJson(1, 'Manga')],
      series: [
        seriesJson(4, 'Berserk', libraryIds: [1]),
        seriesJson(5, 'Monster'),
      ],
    );
    await openSeries(tester, server, 'Berserk');
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Monster'),
        matching: find.text(english.text('manage.no_library')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Berserk'),
        matching: find.text(english.text('manage.no_library')),
      ),
      findsNothing,
    );
  });

  testWidgets('an admin renames a series and gives it a start year', (
    tester,
  ) async {
    final server = ManageServer(
      series: [seriesJson(4, 'berserk', bookCount: 3)],
    );
    await openSeries(tester, server, 'berserk');
    expect(find.text(english.text('manage.edit_series')), findsOneWidget);

    await tester.enterText(field('manage.name'), 'Berserk');
    await tester.enterText(field('manage.start_year'), '1989');
    await save(tester);

    expect(server.changes, [
      'PATCH /api/v1/series/4 {"name":"Berserk","start_release_year":1989}',
    ]);
    // Back on the list, which loaded again.
    expect(find.text('Berserk'), findsOneWidget);
  });

  testWidgets('an emptied year is sent as null, and a year takes digits only', (
    tester,
  ) async {
    final server = ManageServer(
      series: [seriesJson(4, 'Berserk', startYear: 1989)],
    );
    await openSeries(tester, server, 'Berserk');

    await tester.enterText(field('manage.start_year'), '');
    await tester.enterText(field('manage.end_year'), '20x21');
    await save(tester);

    expect(server.changes, [
      'PATCH /api/v1/series/4 {"start_release_year":null,"end_release_year":2021}',
    ]);
  });

  testWidgets('saving without a change sends nothing and closes the form', (
    tester,
  ) async {
    final server = ManageServer(series: [seriesJson(4, 'Berserk')]);
    await openSeries(tester, server, 'Berserk');

    await save(tester);

    expect(server.changes, isEmpty);
    expect(find.text(english.text('manage.edit_series')), findsNothing);
  });

  testWidgets('a series with books is not deleted, and the form says why', (
    tester,
  ) async {
    final server = ManageServer(
      series: [seriesJson(4, 'Berserk', bookCount: 3)],
    );
    await openSeries(tester, server, 'Berserk');

    await deleteConfirmed(tester);

    expect(server.changes, ['DELETE /api/v1/series/4']);
    expect(find.text(english.text('errors.series_not_empty')), findsOneWidget);
    expect(find.text(english.text('manage.edit_series')), findsOneWidget);
  });

  testWidgets('a series without books is deleted', (tester) async {
    final server = ManageServer(
      series: [seriesJson(4, 'Berserk', bookCount: 0)],
    );
    await openSeries(tester, server, 'Berserk');

    await deleteConfirmed(tester);

    expect(server.changes, ['DELETE /api/v1/series/4']);
    expect(find.text(english.text('manage.series_empty')), findsOneWidget);
  });
}
