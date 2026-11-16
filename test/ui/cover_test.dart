import 'dart:async';
import 'dart:ui' as ui;

import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/cover.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../support/fake_server.dart';
import '../support/images.dart';
import '../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });
  setUp(() => PaintingBinding.instance.imageCache.clear());

  final placeholder = find.byIcon(Icons.auto_stories_outlined);

  ui.Image? shown(WidgetTester tester) =>
      tester.widget<RawImage>(find.byType(RawImage)).image;

  /// Shows the series cover of [session] and waits until its image has loaded or failed.
  Future<void> showCover(WidgetTester tester, SessionController session) =>
      tester.runAsync(() async {
        await pumpScreen(
          tester,
          catalog: english,
          screen: Scaffold(
            body: SizedBox(
              width: Covers.maxTileWidth,
              child: Cover(session: session, kind: CoverKind.series, id: 4),
            ),
          ),
        );
        try {
          await loaded(Cover.imageOf(session, CoverKind.series, 4));
        } on Exception {
          // The failure is what some tests look at.
        }
      });

  testWidgets('shows the cover once it has loaded', (tester) async {
    final server = bookServer(
      (_) async => http.Response.bytes(onePixelPng, 200),
    );
    final session = await signedInSession(server);

    await showCover(tester, session);
    await tester.pump();

    expect(shown(tester), isNotNull);
    expect(placeholder, findsNothing);
    expect(server.requests.single.url.path, '/api/v1/covers/series/4');
  });

  testWidgets('shows the placeholder while the cover loads', (tester) async {
    final answer = Completer<http.Response>();
    final session = await signedInSession(bookServer((_) => answer.future));

    await pumpScreen(
      tester,
      catalog: english,
      screen: Cover(session: session, kind: CoverKind.book, id: 1),
    );

    expect(placeholder, findsOneWidget);
    await _endTheRequest(tester, answer);
  });

  testWidgets('shows the placeholder when there is no cover', (tester) async {
    final server = bookServer(
      (_) async => jsonAnswer({'error': 'not_found'}, 404),
    );
    final session = await signedInSession(server);

    await showCover(tester, session);
    await tester.pump();

    expect(placeholder, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the shape of a book cover', (tester) async {
    final answer = Completer<http.Response>();
    final session = await signedInSession(bookServer((_) => answer.future));

    await pumpScreen(
      tester,
      catalog: english,
      screen: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 120,
          child: Cover(session: session, kind: CoverKind.book, id: 1),
        ),
      ),
    );

    expect(tester.getSize(find.byType(Cover)), const Size(120, 180));
    await _endTheRequest(tester, answer);
  });
}

/// Answers a request a test left waiting, so its timeout timer doesn't outlive the test.
Future<void> _endTheRequest(
  WidgetTester tester,
  Completer<http.Response> answer,
) async {
  answer.complete(jsonAnswer({'error': 'not_found'}, 404));
  await tester.pump();
}
