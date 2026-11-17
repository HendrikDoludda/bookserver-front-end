import 'dart:io';

import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/home_screen.dart';
import 'package:bookserver/ui/readers/open_book.dart';
import 'package:bookserver/ui/readers/page_reader.dart';
import 'package:bookserver/ui/readers/pdf_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../support/fake_pdf_engine.dart';
import '../../support/fake_server.dart';
import '../../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });

  Book book(BookFormat format) =>
      Book(id: 7, title: 'Alpha', format: format, volume: 1);

  /// Starts the app signed in, without libraries; book 7 has no pages.
  Future<SessionController> start(WidgetTester tester) async {
    final server = bookServer(
      (request) async => switch (request.url.path) {
        '/api/v1/libraries' || '/api/v1/books/7/pages' => jsonAnswer([]),
        _ => notFound(),
      },
    );
    final session = await pumpApp(
      tester,
      catalog: english,
      store: signedInStore(),
      server: server,
    );
    await tester.pumpAndSettle();
    return session;
  }

  BuildContext home(WidgetTester tester) =>
      tester.element(find.byType(HomeScreen));

  for (final format in [BookFormat.cbz, BookFormat.imageComic]) {
    testWidgets('a ${format.name} book opens in the page reader', (
      tester,
    ) async {
      final session = await start(tester);

      openBook(home(tester), session, book(format));
      await tester.pumpAndSettle();

      expect(find.byType(PageReader), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Alpha'), findsOneWidget);
    });
  }

  testWidgets('a pdf book opens in the PDF reader', (tester) async {
    PdfrxEntryFunctions.instance = FakePdfEngine();
    final temp = Directory.systemTemp.createTempSync('bookserver-pdf-');
    addTearDown(() => temp.deleteSync(recursive: true));
    Pdfrx.cacheDirectoryPath = temp.path;
    final session = await start(tester);

    openBook(home(tester), session, book(BookFormat.pdf));
    await finishTransition(tester);

    expect(find.byType(PdfReader), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Alpha'), findsOneWidget);
  });

  for (final format in [BookFormat.epub, BookFormat.unsupported]) {
    testWidgets("a ${format.name} book says the app can't show it yet", (
      tester,
    ) async {
      final session = await start(tester);

      openBook(home(tester), session, book(format));
      await tester.pumpAndSettle();

      expect(find.text(english.text('reader.unsupported')), findsOneWidget);
      expect(find.byType(HomeScreen), findsOneWidget, reason: 'nothing opened');
    });
  }

  testWidgets('a second such book replaces the message instead of queueing', (
    tester,
  ) async {
    final session = await start(tester);

    openBook(home(tester), session, book(BookFormat.epub));
    await tester.pumpAndSettle();
    openBook(home(tester), session, book(BookFormat.unsupported));
    await tester.pumpAndSettle();

    expect(find.text(english.text('reader.unsupported')), findsOneWidget);
  });
}
