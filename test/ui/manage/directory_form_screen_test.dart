import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/manage/directory_form_screen.dart';
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

  Finder field(String labelKey) =>
      find.widgetWithText(TextField, english.text(labelKey));

  /// Starts the app signed in as an admin, opens Manage's folders and the form for a new one, and
  /// types [path].
  Future<void> newFolder(
    WidgetTester tester,
    ManageServer server,
    String path,
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
    await tester.tap(find.text(english.text('manage.folders')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(english.text('manage.add_folder')));
    await tester.pumpAndSettle();
    await tester.enterText(field('manage.folder_path'), path);
    await tester.pump();
  }

  /// The library name the form shows.
  String libraryName(WidgetTester tester) =>
      tester.widget<TextField>(field('manage.library_name')).controller!.text;

  Future<void> add(WidgetTester tester) async {
    await tester.tap(
      find.widgetWithText(TextButton, english.text('manage.add')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a folder with a library of its own: of the type chosen, named after the folder',
    (tester) async {
      final server = ManageServer();
      await newFolder(tester, server, '/books/Manga');
      expect(libraryName(tester), 'Manga');

      await tester.tap(find.text(english.text('manage.type_books')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(english.text('manage.type_comics')).last);
      await tester.pumpAndSettle();
      await add(tester);

      expect(server.changes, [
        'POST /api/v1/directories '
            '{"path":"/books/Manga","create_library":true,"library_type":"comics",'
            '"library_name":"Manga"}',
      ]);
      // Back on the list, which loaded again.
      expect(find.text('/books/Manga'), findsOneWidget);
      expect(
        find.text(english.text('manage.folder_library', {'library': 'Manga'})),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'the library name follows the folder until another is typed, and again once it is cleared',
    (tester) async {
      await newFolder(tester, ManageServer(), '/books/Manga');

      await tester.enterText(field('manage.library_name'), 'Japanese comics');
      await tester.enterText(field('manage.folder_path'), '/books/Comics');
      await tester.pump();
      expect(libraryName(tester), 'Japanese comics');

      await tester.enterText(field('manage.library_name'), '');
      await tester.enterText(field('manage.folder_path'), r'C:\Books\Comics\');
      await tester.pump();
      expect(libraryName(tester), 'Comics');
    },
  );

  testWidgets('an emptied library name is left to the server', (tester) async {
    final server = ManageServer();
    await newFolder(tester, server, '/books/Manga');

    await tester.enterText(field('manage.library_name'), ' ');
    await add(tester);

    expect(server.changes, [
      'POST /api/v1/directories '
          '{"path":"/books/Manga","create_library":true,"library_type":"books"}',
    ]);
  });

  testWidgets(
    'a folder without a library of its own is sent without a type or a name',
    (tester) async {
      final server = ManageServer();
      await newFolder(tester, server, '/books/inbox');

      await tester.tap(find.text(english.text('manage.own_library')));
      await tester.pump();
      expect(find.text(english.text('manage.own_library_off')), findsOneWidget);
      expect(field('manage.library_name'), findsNothing);
      await add(tester);

      expect(server.changes, [
        'POST /api/v1/directories {"path":"/books/inbox","create_library":false}',
      ]);
      expect(
        find.text(english.text('manage.folder_no_library')),
        findsOneWidget,
      );
    },
  );

  testWidgets('a refused folder stays in the form, which says why', (
    tester,
  ) async {
    final server = ManageServer();
    await newFolder(tester, server, '/books');

    for (final (status, key) in [
      (400, 'directory_not_found'),
      (409, 'directory_taken'),
      (409, 'directory_overlaps'),
    ]) {
      server.refuse = (request) =>
          request.method == 'POST' ? jsonAnswer({'error': key}, status) : null;
      await add(tester);

      expect(find.text(english.text('errors.$key')), findsOneWidget);
      expect(
        find.widgetWithText(AppBar, english.text('manage.add_folder')),
        findsOneWidget,
        reason: 'still the form after $key',
      );
    }
    expect(server.directories, isEmpty);
  });

  test("a folder's name is its path's last part, whichever slash it uses", () {
    expect(folderName('/books/Manga'), 'Manga');
    expect(folderName('/books/Manga/'), 'Manga');
    expect(folderName(r'C:\Books\Comics'), 'Comics');
    expect(folderName('/'), '');
    expect(folderName(''), '');
  });
}
