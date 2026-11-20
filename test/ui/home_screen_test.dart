import 'dart:async';

import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/series_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../support/fake_server.dart';
import '../support/memory_session_store.dart';
import '../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });
  // Every test asks the same server for the same covers: none may come from a test before.
  setUp(() => PaintingBinding.instance.imageCache.clear());

  /// Libraries numbered from 1, each with one series unless [seriesCounts] names its number.
  http.Response libraries(
    List<String> names, {
    Map<String, int> seriesCounts = const {},
  }) => jsonAnswer([
    for (final (index, name) in names.indexed)
      {'id': index + 1, 'name': name, 'series_count': seriesCounts[name] ?? 1},
  ]);

  VoidCallback? reloadAction(WidgetTester tester) => tester
      .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh))
      .onPressed;

  Future<void> start(
    WidgetTester tester,
    FakeServer server, [
    MemorySessionStore? store,
  ]) => pumpApp(
    tester,
    catalog: english,
    store: store ?? signedInStore(),
    server: server,
  );

  testWidgets('lists the libraries by name', (tester) async {
    final server = bookServer(
      (request) async => switch (request.url.path) {
        '/api/v1/libraries' => libraries(['Manga', 'Comics']),
        _ => notFound(),
      },
    );
    await start(tester, server);
    await tester.pumpAndSettle();

    expect(find.text('Manga'), findsOneWidget);
    expect(find.text('Comics'), findsOneWidget);
    expect(requestedPaths(server), ['/api/v1/libraries']);
    final request = server.requests.first;
    expect(request.method, 'GET');
    expect(request.headers['authorization'], 'Bearer session-1');
  });

  testWidgets('shows how many series each library holds under its name', (
    tester,
  ) async {
    final counts = {'Manga': 1, 'Comics': 0, 'Novels': 3};
    final server = bookServer(
      (request) async => switch (request.url.path) {
        '/api/v1/libraries' => libraries([
          ...counts.keys,
        ], seriesCounts: counts),
        _ => notFound(),
      },
    );
    await start(tester, server);
    await tester.pumpAndSettle();

    for (final MapEntry(key: name, value: count) in counts.entries) {
      expect(
        find.descendant(
          of: cardNamed(name),
          matching: find.text(english.plural('browse.series_count', count)),
        ),
        findsOneWidget,
        reason: name,
      );
    }
  });

  testWidgets("shows each library's cover, loaded with the session", (
    tester,
  ) async {
    final server = bookServer(
      (request) async => switch (request.url.path) {
        '/api/v1/libraries' => libraries(['Manga', 'Comics']),
        _ => notFound(),
      },
    );
    await start(tester, server);
    await tester.pumpAndSettle();

    expect(
      requestedCovers(server),
      unorderedEquals(['/api/v1/covers/library/1', '/api/v1/covers/library/2']),
    );
    for (final request in server.requests) {
      expect(request.headers['authorization'], 'Bearer session-1');
    }
  });

  testWidgets('says so when there are no libraries', (tester) async {
    await start(tester, bookServer((_) async => libraries([])));
    await tester.pumpAndSettle();

    expect(find.text(english.text('home.empty')), findsOneWidget);
  });

  testWidgets('shows progress while the libraries load', (tester) async {
    final answer = Completer<http.Response>();
    await start(
      tester,
      bookServer(
        (request) => switch (request.url.path) {
          '/api/v1/libraries' => answer.future,
          _ => Future.value(notFound()),
        },
      ),
    );
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(reloadAction(tester), isNull, reason: 'one load at a time');

    answer.complete(libraries(['Manga']));
    await tester.pumpAndSettle();

    expect(find.text('Manga'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(reloadAction(tester), isNotNull);
  });

  testWidgets('Reload loads the list again and shows the old one meanwhile', (
    tester,
  ) async {
    final second = Completer<http.Response>();
    var calls = 0;
    final server = bookServer(
      (request) => switch (request.url.path) {
        '/api/v1/libraries' =>
          ++calls == 1 ? Future.value(libraries(['Manga'])) : second.future,
        _ => Future.value(notFound()),
      },
    );
    await start(tester, server);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(english.text('home.reload')));
    await tester.pump();

    expect(find.text('Manga'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(reloadAction(tester), isNull, reason: 'one load at a time');

    second.complete(libraries(['Manga', 'Comics']));
    await tester.pumpAndSettle();

    expect(find.text('Comics'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(requestedPaths(server), ['/api/v1/libraries', '/api/v1/libraries']);
  });

  testWidgets('says why the libraries didn\'t load, with Reload under it', (
    tester,
  ) async {
    var calls = 0;
    final server = bookServer(
      (request) async => switch (request.url.path) {
        '/api/v1/libraries' =>
          ++calls == 1 ? http.Response('', 503) : libraries(['Manga']),
        _ => notFound(),
      },
    );
    await start(tester, server);
    await tester.pumpAndSettle();

    expect(find.text(english.text('connection.unreachable')), findsOneWidget);
    expect(find.text('Manga'), findsNothing);

    await tester.tap(
      find.widgetWithText(FilledButton, english.text('home.reload')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Manga'), findsOneWidget);
    expect(find.text(english.text('connection.unreachable')), findsNothing);
    expect(requestedPaths(server), hasLength(2));
  });

  testWidgets('shows the reason the server gives for refusing', (tester) async {
    await start(
      tester,
      bookServer((_) async => jsonAnswer({'error': 'internal_error'}, 500)),
    );
    await tester.pumpAndSettle();

    expect(find.text(english.text('errors.internal_error')), findsOneWidget);
  });

  testWidgets('renews a session token about to run out before loading', (
    tester,
  ) async {
    final store = signedInStore(sessionLasts: const Duration(seconds: 30));
    final server = bookServer(
      (request) async => switch (request.url.path) {
        '/api/v1/auth/refresh' => jsonAnswer(
          tokensJson(session: 'session-2', refresh: 'refresh-2'),
        ),
        '/api/v1/libraries' => libraries(['Manga']),
        _ => notFound(),
      },
    );
    await start(tester, server, store);
    await tester.pumpAndSettle();

    expect(find.text('Manga'), findsOneWidget);
    expect(requestedPaths(server), [
      '/api/v1/auth/refresh',
      '/api/v1/libraries',
    ]);
    expect(server.requests.first.headers['authorization'], 'Bearer refresh-1');
    expect(server.requests[1].headers['authorization'], 'Bearer session-2');
    expect(store.connection?.tokens?.sessionToken, 'session-2');
  });

  testWidgets('a session the server ended leads to the login screen', (
    tester,
  ) async {
    final store = signedInStore();
    final server = bookServer(
      (_) async => jsonAnswer({'error': 'unauthorized'}, 401),
    );
    await start(tester, server, store);
    await tester.pumpAndSettle();

    expect(find.text(english.text('login.username_or_email')), findsOneWidget);
    expect(find.text(english.text('errors.unauthorized')), findsOneWidget);
    expect(requestedPaths(server), [
      '/api/v1/libraries',
      '/api/v1/auth/refresh',
    ]);
    expect(store.connection?.tokens, isNull);
  });

  testWidgets('signing out leads back to the login screen', (tester) async {
    final store = signedInStore();
    final server = bookServer(
      (request) async => switch (request.url.path) {
        '/api/v1/libraries' => libraries(['Manga']),
        '/api/v1/auth/logout' => http.Response('', 204),
        _ => notFound(),
      },
    );
    await start(tester, server, store);
    await tester.pumpAndSettle();
    expect(find.text(english.text('home.title')), findsOneWidget);

    await chooseInUserMenu(tester, english, 'menu.sign_out');
    await tester.pumpAndSettle();

    expect(find.text(english.text('login.username_or_email')), findsOneWidget);
    expect(store.connection?.tokens, isNull);
    expect(store.connection?.deviceId, 'device-1');
    expect(requestedPaths(server), [
      '/api/v1/libraries',
      '/api/v1/auth/logout',
    ]);
    expect(server.requests.last.headers['authorization'], 'Bearer refresh-1');
  });

  testWidgets('a list that arrives after signing out is dropped', (
    tester,
  ) async {
    final answer = Completer<http.Response>();
    final server = bookServer(
      (request) => switch (request.url.path) {
        '/api/v1/libraries' => answer.future,
        _ => Future.value(http.Response('', 204)),
      },
    );
    await start(tester, server);
    await tester.pump();

    await chooseInUserMenu(tester, english, 'menu.sign_out');
    await tester.pumpAndSettle();
    answer.complete(libraries(['Manga']));
    await tester.pumpAndSettle();

    expect(find.text(english.text('login.username_or_email')), findsOneWidget);
    expect(find.text('Manga'), findsNothing);
  });

  testWidgets("a tap on a library opens its series under the library's name", (
    tester,
  ) async {
    final server = bookServer(
      (request) async => switch (request.url.path) {
        '/api/v1/libraries' => libraries(['Manga', 'Comics']),
        '/api/v1/libraries/2/series' => jsonAnswer([]),
        _ => notFound(),
      },
    );
    await start(tester, server);
    await tester.pumpAndSettle();

    await tester.tap(cardNamed('Comics'));
    await tester.pumpAndSettle();

    expect(find.byType(SeriesScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Comics'), findsOneWidget);
    expect(requestedPaths(server), [
      '/api/v1/libraries',
      '/api/v1/libraries/2/series',
    ]);
  });
}
