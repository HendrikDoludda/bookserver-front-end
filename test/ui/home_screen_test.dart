import 'package:bookserver/data/auth_api.dart';
import 'package:bookserver/data/session.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/memory_session_store.dart';
import '../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });

  testWidgets('signing out leads back to the login screen', (tester) async {
    final store = MemorySessionStore()
      ..connection = StoredConnection(
        server: testOrigin,
        deviceId: 'device-1',
      ).withTokens(SessionTokens.fromJson(tokensJson()));
    final server = bookServer((_) async => http.Response('', 204));
    await pumpApp(tester, catalog: english, store: store, server: server);
    expect(find.text(english.text('home.title')), findsOneWidget);

    await tester.tap(find.byTooltip(english.text('home.sign_out')));
    await tester.pumpAndSettle();

    expect(find.text(english.text('login.username_or_email')), findsOneWidget);
    expect(store.connection?.tokens, isNull);
    expect(store.connection?.deviceId, 'device-1');
    final logout = server.requests.single;
    expect(logout.url.path, '/api/v1/auth/logout');
    expect(logout.headers['authorization'], 'Bearer refresh-1');
  });
}
