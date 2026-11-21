import 'package:bookserver/i18n/catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fake_server.dart';
import '../../support/manage_server.dart';
import '../../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });
  setUp(() => PaintingBinding.instance.imageCache.clear());

  /// Starts the app signed in as an admin and opens Manage's list of libraries.
  Future<void> openLibraries(WidgetTester tester, ManageServer server) async {
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
    await tester.tap(find.text(english.text('manage.libraries')));
    await tester.pumpAndSettle();
  }

  Finder field(String labelKey) =>
      find.widgetWithText(TextField, english.text(labelKey));

  Finder seriesBox(String name) => find.widgetWithText(CheckboxListTile, name);

  Future<void> save(WidgetTester tester) async {
    await tester.tap(
      find.widgetWithText(TextButton, english.text('manage.save')),
    );
    await tester.pumpAndSettle();
  }

  Future<void> newLibrary(WidgetTester tester, String name) async {
    await tester.tap(find.byTooltip(english.text('manage.new_library')));
    await tester.pumpAndSettle();
    await tester.enterText(field('manage.name'), name);
  }

  testWidgets('an admin creates a library and puts two series into it', (
    tester,
  ) async {
    final server = ManageServer(
      libraries: [libraryJson(1, 'Manga', type: 'comics')],
      series: [
        seriesJson(4, 'Berserk', libraryIds: [1]),
        seriesJson(5, 'Monster'),
        seriesJson(6, 'Pluto'),
      ],
    );
    await openLibraries(tester, server);

    await newLibrary(tester, 'Favourites');
    await tester.tap(find.text(english.text('manage.type_books')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(english.text('manage.type_comics')).last);
    await tester.pumpAndSettle();
    await tester.enterText(field('manage.description'), 'Picked by hand');
    await tester.tap(seriesBox('Berserk'));
    await tester.tap(seriesBox('Monster'));
    await tester.pump();
    await save(tester);

    expect(server.changes, [
      'POST /api/v1/libraries '
          '{"name":"Favourites","library_type":"comics","description":"Picked by hand"}',
      'PUT /api/v1/libraries/100/series/4',
      'PUT /api/v1/libraries/100/series/5',
    ]);
    // Back on the list, which loaded again.
    expect(find.text('Favourites'), findsOneWidget);
    expect(find.text(english.plural('browse.series_count', 2)), findsOneWidget);
  });

  testWidgets('the series in no library come first, marked as such', (
    tester,
  ) async {
    final server = ManageServer(
      libraries: [libraryJson(1, 'Manga')],
      series: [
        seriesJson(4, 'Berserk', libraryIds: [1]),
        seriesJson(5, 'Monster'),
      ],
    );
    await openLibraries(tester, server);

    await newLibrary(tester, 'Favourites');

    final monster = tester.getTopLeft(seriesBox('Monster')).dy;
    final berserk = tester.getTopLeft(seriesBox('Berserk')).dy;
    expect(monster, lessThan(berserk));
    expect(
      find.descendant(
        of: seriesBox('Monster'),
        matching: find.text(english.text('manage.no_library')),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'editing sends only what changed: the name, the cleared description, the series taken out',
    (tester) async {
      final server = ManageServer(
        libraries: [
          libraryJson(
            1,
            'Manga',
            type: 'comics',
            description: 'Japanese comics',
          ),
        ],
        series: [
          seriesJson(4, 'Berserk', libraryIds: [1]),
          seriesJson(5, 'Monster', libraryIds: [1]),
        ],
      );
      await openLibraries(tester, server);
      await tester.tap(find.text('Manga'));
      await tester.pumpAndSettle();
      expect(find.text(english.text('manage.edit_library')), findsOneWidget);

      await tester.enterText(field('manage.name'), 'Manga & more');
      await tester.enterText(field('manage.description'), '');
      await tester.tap(seriesBox('Monster'));
      await tester.pump();
      await save(tester);

      expect(server.changes, [
        'PATCH /api/v1/libraries/1 {"name":"Manga & more","description":null}',
        'DELETE /api/v1/libraries/1/series/5',
      ]);
      expect(find.text('Manga & more'), findsOneWidget);
    },
  );

  testWidgets(
    'a save that failed after creating changes that library when tried again',
    (tester) async {
      final server = ManageServer(
        series: [seriesJson(4, 'Berserk'), seriesJson(5, 'Monster')],
      );
      var refuseOnce = true;
      server.refuse = (request) {
        if (refuseOnce &&
            request.method == 'PUT' &&
            request.url.path.endsWith('/series/5')) {
          refuseOnce = false;
          return jsonAnswer({'error': 'internal_error'}, 500);
        }
        return null;
      };
      await openLibraries(tester, server);
      await newLibrary(tester, 'Favourites');
      await tester.tap(seriesBox('Berserk'));
      await tester.tap(seriesBox('Monster'));
      await tester.pump();

      await save(tester);
      expect(find.text(english.text('errors.internal_error')), findsOneWidget);
      expect(find.text(english.text('manage.new_library')), findsOneWidget);

      await save(tester);
      expect(server.changes, [
        'POST /api/v1/libraries '
            '{"name":"Favourites","library_type":"books","description":null}',
        'PUT /api/v1/libraries/100/series/4',
        'PUT /api/v1/libraries/100/series/5',
        'PUT /api/v1/libraries/100/series/5',
      ]);
      expect(find.text('Favourites'), findsOneWidget);
    },
  );

  testWidgets('a blank name is refused with its reason, and the form stays', (
    tester,
  ) async {
    final server = ManageServer();
    server.refuse = (request) => request.method == 'POST'
        ? jsonAnswer({'error': 'invalid_name'}, 400)
        : null;
    await openLibraries(tester, server);

    await newLibrary(tester, '   ');
    await save(tester);

    expect(find.text(english.text('errors.invalid_name')), findsOneWidget);
    expect(find.text(english.text('manage.new_library')), findsOneWidget);
  });

  testWidgets('deleting a library asks first, and only Delete deletes it', (
    tester,
  ) async {
    final server = ManageServer(
      libraries: [libraryJson(1, 'Manga')],
      series: [
        seriesJson(4, 'Berserk', libraryIds: [1]),
      ],
    );
    await openLibraries(tester, server);
    await tester.tap(find.text('Manga'));
    await tester.pumpAndSettle();
    Finder deleteButton() =>
        find.widgetWithText(OutlinedButton, english.text('manage.delete'));

    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    expect(
      find.text(english.text('manage.delete_library_explanation')),
      findsOneWidget,
    );
    await tester.tap(find.text(english.text('manage.cancel')));
    await tester.pumpAndSettle();
    expect(server.changes, isEmpty);

    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, english.text('manage.delete')),
    );
    await tester.pumpAndSettle();

    expect(server.changes, ['DELETE /api/v1/libraries/1']);
    expect(find.text(english.text('manage.libraries_empty')), findsOneWidget);
  });
}
