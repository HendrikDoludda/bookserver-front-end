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

  /// Starts the app signed in as an admin and opens Manage's list of folders.
  Future<void> openFolders(WidgetTester tester, ManageServer server) async {
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
    await tester.tap(find.text(english.text('manage.folders')));
    await tester.pumpAndSettle();
  }

  Finder removeButton(String path) => find.descendant(
    of: find.widgetWithText(ListTile, path),
    matching: find.byTooltip(english.text('manage.remove')),
  );

  Future<void> askToRemove(WidgetTester tester, String path) async {
    await tester.tap(removeButton(path));
    await tester.pumpAndSettle();
  }

  testWidgets('the list shows each folder with the library its series join', (
    tester,
  ) async {
    final server = ManageServer(
      libraries: [libraryJson(1, 'Manga')],
      directories: [
        directoryJson(2, '/books/manga', libraryId: 1),
        directoryJson(3, '/books/inbox'),
      ],
    );
    await openFolders(tester, server);

    expect(find.text('/books/manga'), findsOneWidget);
    expect(
      find.text(english.text('manage.folder_library', {'library': 'Manga'})),
      findsOneWidget,
    );
    expect(find.text('/books/inbox'), findsOneWidget);
    expect(find.text(english.text('manage.folder_no_library')), findsOneWidget);
  });

  testWidgets('without folders, the list says how to start', (tester) async {
    await openFolders(tester, ManageServer());

    expect(find.text(english.text('manage.folders_empty')), findsOneWidget);
  });

  testWidgets('removing a folder asks first, and sends the DELETE only then', (
    tester,
  ) async {
    final server = ManageServer(
      directories: [
        directoryJson(2, '/books/manga'),
        directoryJson(3, '/books/inbox'),
      ],
    );
    await openFolders(tester, server);

    await askToRemove(tester, '/books/manga');
    expect(
      find.text(english.text('manage.remove_folder_explanation')),
      findsOneWidget,
    );
    await tester.tap(
      find.widgetWithText(TextButton, english.text('manage.cancel')),
    );
    await tester.pumpAndSettle();
    expect(server.changes, isEmpty);

    await askToRemove(tester, '/books/manga');
    await tester.tap(
      find.widgetWithText(FilledButton, english.text('manage.remove')),
    );
    await tester.pumpAndSettle();

    expect(server.changes, ['DELETE /api/v1/directories/2']);
    // The list loaded again.
    expect(find.text('/books/manga'), findsNothing);
    expect(find.text('/books/inbox'), findsOneWidget);
  });

  testWidgets('a removal the server refuses says why, and the folder stays', (
    tester,
  ) async {
    final server = ManageServer(directories: [directoryJson(2, '/books/manga')])
      ..refuse = (request) => request.method == 'DELETE' ? notFound() : null;
    await openFolders(tester, server);

    await askToRemove(tester, '/books/manga');
    await tester.tap(
      find.widgetWithText(FilledButton, english.text('manage.remove')),
    );
    await tester.pumpAndSettle();

    expect(find.text(english.text('errors.not_found')), findsOneWidget);
    expect(find.text('/books/manga'), findsOneWidget);
  });
}
