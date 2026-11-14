import 'dart:async';
import 'dart:io';

import 'package:bookserver/i18n/catalog.dart';
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

  Finder addressField() => find.byType(TextField);
  Finder connectButton() =>
      find.widgetWithText(FilledButton, english.text('server.connect'));
  Finder loginScreen() => find.text(english.text('login.username_or_email'));

  testWidgets('a book server leads on to the login screen', (tester) async {
    final store = MemorySessionStore();
    await pumpApp(tester, catalog: english, store: store, server: bookServer());

    await tester.enterText(addressField(), 'books.example.ts.net');
    await tester.tap(connectButton());
    await tester.pumpAndSettle();

    expect(loginScreen(), findsOneWidget);
    expect(store.connection?.server, testOrigin);
  });

  testWidgets('Enter in the field connects', (tester) async {
    await pumpApp(
      tester,
      catalog: english,
      store: MemorySessionStore(),
      server: bookServer(),
    );

    await tester.enterText(addressField(), testAddress);
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();

    expect(loginScreen(), findsOneWidget);
  });

  testWidgets('shows that it is busy while it checks the address', (
    tester,
  ) async {
    final health = Completer<http.Response>();
    await pumpApp(
      tester,
      catalog: english,
      store: MemorySessionStore(),
      server: FakeServer((_) => health.future),
    );

    await tester.enterText(addressField(), testAddress);
    await tester.tap(connectButton());
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(connectButton()).onPressed, isNull);
    expect(tester.widget<TextField>(addressField()).enabled, isFalse);

    health.complete(http.Response('pong', 200));
    await tester.pumpAndSettle();

    expect(loginScreen(), findsOneWidget);
  });

  group('says why it refused an address', () {
    Future<void> tryAddress(
      WidgetTester tester,
      String address, {
      FakeServer? server,
      bool allowHttp = true,
    }) async {
      await pumpApp(
        tester,
        catalog: english,
        store: MemorySessionStore(),
        server: server ?? bookServer(),
        allowHttp: allowHttp,
      );
      await tester.enterText(addressField(), address);
      await tester.tap(connectButton());
      await tester.pumpAndSettle();
    }

    void expectRefusal(WidgetTester tester, String key) {
      expect(find.text(english.text(key)), findsOneWidget);
      expect(find.text(english.text('server.title')), findsOneWidget);
      expect(tester.widget<TextField>(addressField()).enabled, isTrue);
      expect(tester.widget<FilledButton>(connectButton()).onPressed, isNotNull);
    }

    testWidgets('an address that is none', (tester) async {
      await tryAddress(tester, 'not a server');
      expectRefusal(tester, 'server.invalid_address');
    });

    testWidgets('http:// in a release build', (tester) async {
      await tryAddress(tester, 'http://localhost:8080', allowHttp: false);
      expectRefusal(tester, 'server.insecure_address');
    });

    testWidgets('an address where no book server answers', (tester) async {
      await tryAddress(
        tester,
        testAddress,
        server: FakeServer((_) async => http.Response('Not found', 404)),
      );
      expectRefusal(tester, 'server.not_a_bookserver');
    });

    testWidgets('an address where nothing answers', (tester) async {
      await tryAddress(
        tester,
        testAddress,
        server: FakeServer(
          (_) async => throw const SocketException('Connection refused'),
        ),
      );
      expectRefusal(tester, 'connection.unreachable');
    });
  });
}
