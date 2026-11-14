import 'package:bookserver/app.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import 'fake_server.dart';
import 'memory_session_store.dart';

const testAddress = 'https://books.example.ts.net';
final testOrigin = Uri.parse(testAddress);

/// A login or refresh answer whose session token runs another 15 minutes.
Map<String, Object?> tokensJson({
  String session = 'session-1',
  String refresh = 'refresh-1',
}) {
  final now = DateTime.now();
  return {
    'session_token': session,
    'session_expires_at': _seconds(now.add(const Duration(minutes: 15))),
    'refresh_token': refresh,
    'refresh_expires_at': _seconds(now.add(const Duration(days: 30))),
    'device_id': 'device-1',
  };
}

/// A book server: `/health` answers pong, every other request gets [answer]'s response.
FakeServer bookServer([
  Future<http.Response> Function(http.Request request)? answer,
]) => FakeServer((request) async {
  if (request.url.path == '/health') {
    return http.Response('pong', 200);
  }
  if (answer == null) {
    return jsonAnswer({'error': 'not_found'}, 404);
  }
  return answer(request);
});

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
