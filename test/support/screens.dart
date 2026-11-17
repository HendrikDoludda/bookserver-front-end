import 'package:bookserver/app.dart';
import 'package:bookserver/data/auth_api.dart';
import 'package:bookserver/data/session.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/cover_grid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import 'fake_server.dart';
import 'memory_session_store.dart';

const testAddress = 'https://books.example.ts.net';
final testOrigin = Uri.parse(testAddress);

/// A login or refresh answer whose session token runs another [sessionLasts].
Map<String, Object?> tokensJson({
  String session = 'session-1',
  String refresh = 'refresh-1',
  Duration sessionLasts = const Duration(minutes: 15),
}) {
  final now = DateTime.now();
  return {
    'session_token': session,
    'session_expires_at': _seconds(now.add(sessionLasts)),
    'refresh_token': refresh,
    'refresh_expires_at': _seconds(now.add(const Duration(days: 30))),
    'device_id': 'device-1',
  };
}

/// The server's answer for something that doesn't exist, such as a missing cover.
http.Response notFound() => jsonAnswer({'error': 'not_found'}, 404);

/// A book server: `/health` answers pong, every other request gets [answer]'s response.
FakeServer bookServer([
  Future<http.Response> Function(http.Request request)? answer,
]) => FakeServer((request) async {
  if (request.url.path == '/health') {
    return http.Response('pong', 200);
  }
  if (answer == null) {
    return notFound();
  }
  return answer(request);
});

/// What [server] was asked for besides covers, which every card on a browse screen asks for.
List<String> requestedPaths(FakeServer server) => [
  for (final request in server.requests)
    if (!_isCover(request)) request.url.path,
];

/// The covers [server] was asked for.
List<String> requestedCovers(FakeServer server) => [
  for (final request in server.requests)
    if (_isCover(request)) request.url.path,
];

bool _isCover(http.BaseRequest request) =>
    request.url.path.startsWith('/api/v1/covers/');

/// A stored record signed in to [testOrigin], its session token good for another [sessionLasts].
MemorySessionStore signedInStore({
  Duration sessionLasts = const Duration(minutes: 15),
}) => MemorySessionStore()
  ..connection = StoredConnection(
    server: testOrigin,
    deviceId: 'device-1',
  ).withTokens(SessionTokens.fromJson(tokensJson(sessionLasts: sessionLasts)));

/// A session signed in to [server], its session token good for another [sessionLasts].
Future<SessionController> signedInSession(
  FakeServer server, {
  Duration sessionLasts = const Duration(minutes: 15),
}) async {
  final session = SessionController(
    store: signedInStore(sessionLasts: sessionLasts),
    client: server.client,
    platform: 'macos',
  );
  await session.load();
  return session;
}

/// The card named [name], to tap: the card's ink layer lies over its name, so the name's text
/// itself never gets the tap.
Finder cardNamed(String name) => find.widgetWithText(CoverCard, name);

/// Lets a pushed screen's transition finish while a list it loads is still on its way, which
/// `pumpAndSettle` can't wait out: the loading bar never stops moving.
Future<void> finishTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// Starts the whole app as `main()` does, on [store]'s record and [server].
Future<SessionController> pumpApp(
  WidgetTester tester, {
  required Catalog catalog,
  required MemorySessionStore store,
  required FakeServer server,
  bool allowHttp = true,
}) async {
  final session = SessionController(
    store: store,
    client: server.client,
    allowHttp: allowHttp,
    platform: 'macos',
  );
  await session.load();
  await tester.pumpWidget(BookserverApp(catalog: catalog, session: session));
  return session;
}

/// Shows one screen under the catalog, outside the app's stage switch.
Future<void> pumpScreen(
  WidgetTester tester, {
  required Catalog catalog,
  required Widget screen,
}) => tester.pumpWidget(
  CatalogScope(
    catalog: catalog,
    child: MaterialApp(home: screen),
  ),
);

int _seconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;
