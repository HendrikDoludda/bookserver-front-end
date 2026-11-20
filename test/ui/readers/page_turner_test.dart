import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/readers/page_turner.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });

  /// The pages the turner said it landed on, in order.
  final turns = <int>[];
  var taps = 0;
  setUp(() {
    turns.clear();
    taps = 0;
  });

  /// The page on screen, as the turner reported it.
  int current() => turns.lastOrNull ?? 0;

  /// Shows a [PageTurner] of [count] plain boxes, each saying its index; answers every build of a
  /// page as its index and the decode width it was given, in order.
  Future<List<(int, int)>> showTurner(
    WidgetTester tester, {
    int count = 3,
  }) async {
    final builds = <(int, int)>[];
    await pumpScreen(
      tester,
      catalog: english,
      screen: Scaffold(
        body: PageTurner(
          count: count,
          onPageChanged: turns.add,
          onTap: () => taps++,
          pageBuilder: (context, index, decodeWidth) {
            builds.add((index, decodeWidth));
            return SizedBox.expand(child: Center(child: Text('box $index')));
          },
        ),
      ),
    );
    return builds;
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('opens on the first page and builds the next one ahead', (
    tester,
  ) async {
    final builds = await showTurner(tester);

    expect(find.text('box 0'), findsOneWidget);
    expect(current(), 0);
    expect({for (final (index, _) in builds) index}, {0, 1});
  });

  testWidgets('the arrow keys turn the pages, never past either end', (
    tester,
  ) async {
    await showTurner(tester);

    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(current(), 0);

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(current(), 1);

    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(current(), 2);

    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(current(), 1);
    expect(turns, [1, 2, 1], reason: 'one report per turn');
  });

  testWidgets('a single page turns nowhere', (tester) async {
    await showTurner(tester, count: 1);

    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowLeft);

    expect(find.text('box 0'), findsOneWidget);
    expect(turns, isEmpty);
  });

  testWidgets('a swipe to the left turns forward, one to the right back', (
    tester,
  ) async {
    await showTurner(tester);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(current(), 1);

    await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();
    expect(current(), 0);
  });

  testWidgets('a zoomed page holds still under a swipe; a turn zooms out', (
    tester,
  ) async {
    await showTurner(tester);
    final zoom = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    zoom.value = Matrix4.diagonal3Values(2, 2, 1);
    await tester.pump();

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(current(), 0);

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(current(), 1);
    expect(zoom.value.getMaxScaleOnAxis(), 1);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(current(), 2);
  });

  testWidgets(
    "pages decode at twice the window's shorter side, kept while the window changes",
    (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final builds = await showTurner(tester);

      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 2;
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowRight);

      expect({for (final (index, _) in builds) index}, contains(2));
      expect({for (final (_, width) in builds) width}, {2340});
    },
  );

  testWidgets('a page can turn straight to another, at normal size', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      catalog: english,
      screen: Scaffold(
        body: PageTurner(
          count: 3,
          onPageChanged: turns.add,
          onTap: () => taps++,
          pageBuilder: (context, index, decodeWidth) => Center(
            child: TextButton(
              onPressed: () => PageTurner.of(context).turnTo(2),
              child: Text('box $index'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('box 0'));
    await tester.pumpAndSettle();
    expect(current(), 2);
    expect(taps, 0, reason: 'the button took the tap');

    final zoom = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    zoom.value = Matrix4.diagonal3Values(2, 2, 1);
    await tester.pump();
    final turner = tester.state<PageTurnerState>(find.byType(PageTurner));
    turner.turnTo(0);
    await tester.pumpAndSettle();
    expect(current(), 0);
    expect(zoom.value.getMaxScaleOnAxis(), 1);

    turner.turnTo(3);
    await tester.pumpAndSettle();
    expect(current(), 0, reason: 'a page that does not exist');
  });

  testWidgets('a tap on a page that nothing on it takes is reported', (
    tester,
  ) async {
    await showTurner(tester);

    await tester.tap(find.text('box 0'));
    await tester.pumpAndSettle();

    expect(taps, 1);
    expect(turns, isEmpty, reason: 'a tap turns nothing');
  });

  testWidgets('a swipe is no tap', (tester) async {
    await showTurner(tester);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(taps, 0);
  });

  testWidgets('says whether its pages are moving', (tester) async {
    final builds = await showTurner(tester);
    expect(builds, isNotEmpty);
    final moving = tester
        .state<PageTurnerState>(find.byType(PageTurner))
        .moving;
    expect(moving.value, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(moving.value, isTrue, reason: 'in the middle of a turn');

    await tester.pumpAndSettle();
    expect(moving.value, isFalse);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pump(const Duration(milliseconds: 50));
    expect(moving.value, isTrue, reason: 'in the middle of a swipe');
    await tester.pumpAndSettle();
    expect(moving.value, isFalse);
    expect(current(), 2);
  });

  test('a turner without pages is a mistake', () {
    expect(
      () => PageTurner(
        count: 0,
        pageBuilder: (context, index, decodeWidth) => const SizedBox(),
      ),
      throwsAssertionError,
    );
  });
}
