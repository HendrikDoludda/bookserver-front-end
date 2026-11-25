import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/cover_cache.dart';
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

  Future<void> openCoverChoice(WidgetTester tester) async {
    await tester.tap(find.text(english.text('manage.cover')));
    await tester.pumpAndSettle();
  }

  String volume(int number) =>
      english.text('browse.volume', {'number': number});

  testWidgets('a book picked from the series\' covers is sent on Save', (
    tester,
  ) async {
    final server = ManageServer(
      series: [seriesJson(4, 'Berserk', bookCount: 2)],
      books: {
        4: [bookJson(11, volume: 1), bookJson(12, volume: 2)],
      },
      covers: {'/api/v1/covers/book/11', '/api/v1/covers/book/12'},
    );
    await openSeries(tester, server, 'Berserk');

    await openCoverChoice(tester);
    expect(find.text(english.text('manage.choose_cover')), findsOneWidget);
    await tester.tap(cardNamed(volume(2)));
    await tester.pumpAndSettle();

    expect(find.text(english.text('manage.edit_series')), findsOneWidget);
    expect(find.text(volume(2)), findsOneWidget, reason: 'the form shows it');
    expect(server.changes, isEmpty, reason: 'nothing goes before Save');
    await save(tester);

    expect(server.changes, ['PUT /api/v1/series/4/cover {"book_id":12}']);
  });

  testWidgets('Automatic resets the cover with DELETE, after the fields', (
    tester,
  ) async {
    final server = ManageServer(
      series: [seriesJson(4, 'Berserk')],
      books: {
        4: [bookJson(11, volume: 1)],
      },
    );
    await openSeries(tester, server, 'Berserk');

    await tester.enterText(field('manage.name'), 'Berserk!');
    await openCoverChoice(tester);
    await tester.tap(cardNamed(english.text('manage.cover_automatic')));
    await tester.pumpAndSettle();
    expect(find.text(english.text('manage.cover_automatic')), findsOneWidget);
    await save(tester);

    expect(server.changes, [
      'PATCH /api/v1/series/4 {"name":"Berserk!"}',
      'DELETE /api/v1/series/4/cover',
    ]);
  });

  testWidgets('a book whose cover doesn\'t load can\'t be picked', (
    tester,
  ) async {
    final server = ManageServer(
      series: [seriesJson(4, 'Berserk', bookCount: 2)],
      books: {
        4: [bookJson(11, volume: 1), bookJson(12, volume: 2)],
      },
      covers: {'/api/v1/covers/book/11'},
    );
    await openSeries(tester, server, 'Berserk');
    await openCoverChoice(tester);

    await tester.tap(cardNamed(volume(2)));
    await tester.pumpAndSettle();
    expect(
      find.text(english.text('manage.choose_cover')),
      findsOneWidget,
      reason: 'still choosing',
    );

    await tester.tap(cardNamed(volume(1)));
    await tester.pumpAndSettle();
    await save(tester);
    expect(server.changes, ['PUT /api/v1/series/4/cover {"book_id":11}']);
  });

  testWidgets(
    'saving drops the cached covers of the series and of its libraries, and no others',
    (tester) async {
      final server = ManageServer(
        libraries: [libraryJson(1, 'Manga'), libraryJson(2, 'Other')],
        series: [
          seriesJson(4, 'Berserk', libraryIds: [1]),
          seriesJson(5, 'Monster', libraryIds: [2]),
        ],
        covers: {
          '/api/v1/covers/series/4',
          '/api/v1/covers/library/1',
          '/api/v1/covers/series/5',
          '/api/v1/covers/library/2',
        },
      );
      final session = await signedInSession(server.fake);
      final [berserk, manga, monster, other] = (await tester.runAsync(
        () => cachedCovers(session, [
          (CoverKind.series, 4),
          (CoverKind.library, 1),
          (CoverKind.series, 5),
          (CoverKind.library, 2),
        ]),
      ))!;
      expect([berserk, manga, monster, other].every(isCached), isTrue);
      await openSeries(tester, server, 'Berserk');

      await tester.enterText(field('manage.name'), 'Berserk!');
      await save(tester);

      expect(isCached(berserk), isFalse);
      expect(isCached(manga), isFalse, reason: 'it may fall back to Berserk');
      expect(isCached(monster), isTrue);
      expect(isCached(other), isTrue);
    },
  );

  Future<void> openMergeChoice(WidgetTester tester) async {
    await tester.tap(
      find.widgetWithText(OutlinedButton, english.text('manage.merge_series')),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the choice of series and picks [name], which asks before merging.
  Future<void> chooseMergeTarget(WidgetTester tester, String name) async {
    await openMergeChoice(tester);
    await tester.tap(find.widgetWithText(ListTile, name));
    await tester.pumpAndSettle();
  }

  Future<void> confirmMerge(WidgetTester tester) async {
    await tester.tap(
      find.widgetWithText(FilledButton, english.text('manage.merge')),
    );
    await tester.pumpAndSettle();
  }

  ManageServer hellboyServer() => ManageServer(
    libraries: [libraryJson(1, 'Comics'), libraryJson(2, 'Other')],
    series: [
      seriesJson(4, 'Hellboy BPRD', libraryIds: [1]),
      seriesJson(5, 'hellboybprd', bookCount: 2, libraryIds: [2]),
      seriesJson(6, 'Monster'),
    ],
  );

  testWidgets('the series to merge into is picked from every other one', (
    tester,
  ) async {
    final server = hellboyServer();
    await openSeries(tester, server, 'hellboybprd');

    await openMergeChoice(tester);

    expect(
      find.text(english.text('manage.choose_merge_target')),
      findsOneWidget,
    );
    expect(find.widgetWithText(ListTile, 'Hellboy BPRD'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Monster'), findsOneWidget);
    expect(
      find.widgetWithText(ListTile, 'hellboybprd'),
      findsNothing,
      reason: 'not into itself',
    );
  });

  testWidgets('with no other series, the choice says so', (tester) async {
    final server = ManageServer(series: [seriesJson(4, 'Berserk')]);
    await openSeries(tester, server, 'Berserk');

    await openMergeChoice(tester);

    expect(find.text(english.text('manage.no_merge_target')), findsOneWidget);
  });

  testWidgets(
    'a merge names the series it goes into and is sent once confirmed',
    (tester) async {
      final server = hellboyServer();
      await openSeries(tester, server, 'hellboybprd');

      await chooseMergeTarget(tester, 'Hellboy BPRD');
      expect(
        find.text(
          english.text('manage.merge_series_question', {
            'name': 'Hellboy BPRD',
          }),
        ),
        findsOneWidget,
      );
      expect(server.changes, isEmpty, reason: 'nothing goes before Merge');
      await confirmMerge(tester);

      expect(server.changes, ['POST /api/v1/series/4/merges {"series_id":5}']);
      // Back on the list, which loaded again without the merged series.
      expect(find.text('hellboybprd'), findsNothing);
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Hellboy BPRD'),
          matching: find.text(english.plural('browse.book_count', 3)),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('a cancelled merge sends nothing and leaves the form open', (
    tester,
  ) async {
    final server = hellboyServer();
    await openSeries(tester, server, 'hellboybprd');

    await chooseMergeTarget(tester, 'Hellboy BPRD');
    await tester.tap(
      find.widgetWithText(TextButton, english.text('manage.cancel')),
    );
    await tester.pumpAndSettle();

    expect(server.changes, isEmpty);
    expect(find.text(english.text('manage.edit_series')), findsOneWidget);
  });

  testWidgets('a refused merge leaves the form open and says why', (
    tester,
  ) async {
    final server = hellboyServer()
      ..refuse = (request) => request.method == 'POST'
          ? jsonAnswer({'error': 'not_found'}, 404)
          : null;
    await openSeries(tester, server, 'hellboybprd');

    await chooseMergeTarget(tester, 'Hellboy BPRD');
    await confirmMerge(tester);

    expect(find.text(english.text('errors.not_found')), findsOneWidget);
    expect(find.text(english.text('manage.edit_series')), findsOneWidget);
  });

  testWidgets(
    'merging drops the cached covers of both series and of their libraries, and no others',
    (tester) async {
      final server = ManageServer(
        libraries: [
          libraryJson(1, 'Comics'),
          libraryJson(2, 'Other'),
          libraryJson(3, 'Untouched'),
        ],
        series: [
          seriesJson(4, 'Hellboy BPRD', libraryIds: [1]),
          seriesJson(5, 'hellboybprd', libraryIds: [2]),
          seriesJson(6, 'Monster', libraryIds: [3]),
        ],
        covers: {
          '/api/v1/covers/series/4',
          '/api/v1/covers/series/5',
          '/api/v1/covers/series/6',
          '/api/v1/covers/library/1',
          '/api/v1/covers/library/2',
          '/api/v1/covers/library/3',
        },
      );
      final session = await signedInSession(server.fake);
      final [kept, merged, monster, comics, other, untouched] = (await tester
          .runAsync(
            () => cachedCovers(session, [
              (CoverKind.series, 4),
              (CoverKind.series, 5),
              (CoverKind.series, 6),
              (CoverKind.library, 1),
              (CoverKind.library, 2),
              (CoverKind.library, 3),
            ]),
          ))!;
      expect(
        [kept, merged, monster, comics, other, untouched].every(isCached),
        isTrue,
      );
      await openSeries(tester, server, 'hellboybprd');

      await chooseMergeTarget(tester, 'Hellboy BPRD');
      await confirmMerge(tester);

      expect(isCached(kept), isFalse, reason: 'it may take the merged cover');
      expect(isCached(merged), isFalse);
      expect(
        isCached(comics),
        isFalse,
        reason: 'it may fall back to the kept one',
      );
      expect(isCached(other), isFalse);
      expect(isCached(monster), isTrue);
      expect(isCached(untouched), isTrue);
    },
  );
}
