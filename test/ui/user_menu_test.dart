import 'package:bookserver/i18n/catalog.dart';
import 'package:flutter_test/flutter_test.dart';
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

  /// A server with one library, whose signed-in user has [role].
  FakeServer serverFor(String role) => bookServer(
    (request) async => switch (request.url.path) {
      '/api/v1/libraries' => jsonAnswer([
        {'id': 3, 'name': 'Manga', 'series_count': 1},
      ]),
      '/api/v1/account' => jsonAnswer({
        'id': 1,
        'username': 'alice',
        'email': 'alice@example.com',
        'email_verified': true,
        'role': role,
        'created_at': 1700000000,
        'last_login': null,
      }),
      _ => notFound(),
    },
  );

  Future<void> start(WidgetTester tester, FakeServer server) async {
    await pumpApp(
      tester,
      catalog: english,
      store: signedInStore(),
      server: server,
      followAccount: true,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a member sees Settings and Sign out, but no Manage', (
    tester,
  ) async {
    await start(tester, serverFor('member'));

    await tester.tap(find.byTooltip(english.text('menu.user')));
    await tester.pumpAndSettle();

    expect(find.text(english.text('menu.settings')), findsOneWidget);
    expect(find.text(english.text('menu.sign_out')), findsOneWidget);
    expect(find.text(english.text('menu.manage')), findsNothing);
  });

  testWidgets('an admin opens Manage, which lists libraries and series', (
    tester,
  ) async {
    await start(tester, serverFor('admin'));

    await chooseInUserMenu(tester, english, 'menu.manage');
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(AppBar, english.text('manage.title')),
      findsOneWidget,
    );
    expect(find.text(english.text('manage.libraries')), findsOneWidget);
    expect(find.text(english.text('manage.series')), findsOneWidget);
  });
}
