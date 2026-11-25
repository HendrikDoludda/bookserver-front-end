import 'dart:convert';

import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/readers/page_reader.dart';
import 'package:bookserver/ui/started_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../support/fake_server.dart';
import '../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });
  setUp(() => PaintingBinding.instance.imageCache.clear());

  /// A started book as `GET /api/v1/books/started` sends one: volume [volume] of [seriesName], at
  /// page [position] of 10.
  Map<String, Object?> startedJson(
    int id, {
    required int volume,
    String? seriesName,
    int position = 3,
  }) => {
    'id': id,
    'title': 'Berserk',
    'author': 'Kentaro Miura',
    'format': 'cbz',
    'tags': <String>[],
    'description': null,
    'language': null,
    'page_count': null,
    'series': seriesName == null ? null : 4,
    'volume_number': volume,
    'chapter_number': null,
    'page_number': null,
    'last_modified': null,
    'file_size': null,
    'series_name': seriesName,
    'progress': {'position': position, 'total': 10, 'finished': false},
  };

  /// A server without libraries whose started books come from [started]; a book marked read or
  /// unread goes to [mark].
  FakeServer startedServer(
    List<Map<String, Object?>> Function() started, {
    Future<http.Response> Function(http.Request request)? mark,
  }) => bookServer(
    (request) => switch (request.url.path) {
      '/api/v1/libraries' => Future.value(jsonAnswer([])),
      '/api/v1/books/started' => Future.value(jsonAnswer(started())),
      final path when mark != null && path.endsWith('/progress') => mark(
        request,
      ),
      _ => Future.value(notFound()),
    },
  );

  /// Starts the app signed in and opens Continue reading from the libraries' top bar.
  Future<void> openStarted(WidgetTester tester, FakeServer server) async {
    await pumpApp(
      tester,
      catalog: english,
      store: signedInStore(),
      server: server,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(english.text('home.continue_reading')));
    await tester.pumpAndSettle();
  }

  String volume(int number) =>
      english.text('browse.volume', {'number': number});

  int startedLoads(FakeServer server) =>
      requestedPaths(server)
          .where((path) => path == '/api/v1/books/started')
          .length;

  testWidgets(
    'lists the started books in the order the server sends, each with its series under it',
    (tester) async {
      final server = startedServer(
        () => [
          startedJson(8, volume: 3, seriesName: 'Monster', position: 4),
          startedJson(7, volume: 1, seriesName: 'Berserk'),
          startedJson(9, volume: 2),
        ],
      );

      await openStarted(tester, server);

      expect(find.byType(StartedScreen), findsOneWidget);
      final places = [
        for (final name in [volume(3), volume(1), volume(2)])
          tester.getTopLeft(cardNamed(name)),
      ];
      for (final (index, place) in places.indexed.skip(1)) {
        final before = places[index - 1];
        expect(
          place.dy > before.dy ||
              (place.dy == before.dy && place.dx > before.dx),
          isTrue,
          reason: 'card $index comes after card ${index - 1}',
        );
      }
      expect(
        find.descendant(
          of: cardNamed(volume(3)),
          matching: find.text('Monster'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.descendant(
                of: cardNamed(volume(3)),
                matching: find.byType(LinearProgressIndicator),
              ),
            )
            .value,
        0.5,
        reason: 'page 5 of 10',
      );
    },
  );

  testWidgets('says so when no book is started', (tester) async {
    await openStarted(tester, startedServer(() => []));

    expect(find.text(english.text('home.continue_empty')), findsOneWidget);
  });

  testWidgets(
    'a tap reads on, and the list loads again once the reader closes',
    (tester) async {
      final server = startedServer(
        () => [startedJson(7, volume: 1, seriesName: 'Berserk')],
      );
      await openStarted(tester, server);

      await tester.tap(cardNamed(volume(1)));
      await tester.pumpAndSettle();
      expect(find.byType(PageReader), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(StartedScreen), findsOneWidget);
      expect(startedLoads(server), 2);
    },
  );

  testWidgets('a book marked read by a long press leaves the list', (
    tester,
  ) async {
    var marked = false;
    final marks = <Object?>[];
    final server = startedServer(
      () => [if (!marked) startedJson(7, volume: 1, seriesName: 'Berserk')],
      mark: (request) async {
        marks.add(jsonDecode(request.body));
        marked = true;
        return jsonAnswer({'position': 3, 'total': 10, 'finished': true});
      },
    );
    await openStarted(tester, server);

    await tester.longPress(cardNamed(volume(1)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(english.text('browse.mark_read')));
    await tester.pumpAndSettle();

    expect(marks, [
      {'finished': true},
    ]);
    expect(find.text(english.text('home.continue_empty')), findsOneWidget);
  });
}
