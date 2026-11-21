import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/readers/page_turner.dart';
import 'package:bookserver/ui/readers/zoom.dart';
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
  var pinches = 0;
  setUp(() {
    turns.clear();
    taps = 0;
    pinches = 0;
  });

  /// The page on screen, as the turner reported it.
  int current() => turns.lastOrNull ?? 0;

  /// Shows a [PageTurner] of [count] plain boxes, each saying its index, in a screen written in
  /// [textDirection]; answers every build of a page as its index and the decode width it was
  /// given, in order. Shown again, the turner on screen takes the new settings.
  Future<List<(int, int)>> showTurner(
    WidgetTester tester, {
    int count = 3,
    bool rightToLeft = false,
    TextDirection textDirection = TextDirection.ltr,
    ZoomStep initialZoom = ZoomStep.fitPage,
    double? Function(int index)? pageShape,
  }) async {
    final builds = <(int, int)>[];
    await pumpScreen(
      tester,
      catalog: english,
      screen: Directionality(
        textDirection: textDirection,
        child: Scaffold(
          body: PageTurner(
            count: count,
            rightToLeft: rightToLeft,
            initialZoom: initialZoom,
            pageShape: pageShape,
            onPageChanged: turns.add,
            onTap: () => taps++,
            onPinch: () => pinches++,
            pageBuilder: (context, index, decodeWidth) {
              builds.add((index, decodeWidth));
              return SizedBox.expand(child: Center(child: Text('box $index')));
            },
          ),
        ),
      ),
    );
    return builds;
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  /// Taps the pages [fraction] of their width from their left edge, halfway down.
  Future<void> tapAcross(WidgetTester tester, double fraction) async {
    final pages = tester.getRect(find.byType(PageView));
    await tester.tapAt(
      Offset(pages.left + pages.width * fraction, pages.center.dy),
    );
    await tester.pumpAndSettle();
  }

  /// Where page [index] sits across the screen, built ahead or on screen.
  double across(WidgetTester tester, int index) =>
      tester.getCenter(find.text('box $index', skipOffstage: false)).dx;

  /// The zoom every page shows at.
  Matrix4 zoom(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!
      .value;

  PageTurnerState turner(WidgetTester tester) =>
      tester.state<PageTurnerState>(find.byType(PageTurner));

  Size window(WidgetTester tester) => tester.getSize(find.byType(PageTurner));

  // A page 2:3 and a spread 2:1; in the test window, 800 × 600, the spread is as wide as the
  // window when fitted whole.
  const shapes = [2 / 3, 2.0, 2 / 3];
  double shapeOf(int index) => shapes[index];

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

  testWidgets(
    'a tap on the right edge turns forward, on the left edge back, in the middle is reported',
    (tester) async {
      await showTurner(tester);

      await tapAcross(tester, 0.1);
      expect(turns, isEmpty, reason: 'nothing comes before the first page');

      await tapAcross(tester, 0.9);
      expect(current(), 1);

      await tapAcross(tester, 0.1);
      expect(current(), 0);

      await tapAcross(tester, 0.5);
      expect(taps, 1);
      expect(turns, [1, 0], reason: 'the middle turns nothing');
    },
  );

  testWidgets('right to left, page 1 is at the right, and a swipe to the right, the left arrow and the '
      'left edge go forward', (tester) async {
    await showTurner(tester, rightToLeft: true);
    expect(across(tester, 1), lessThan(across(tester, 0)));

    await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();
    expect(current(), 1);

    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(current(), 2);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(current(), 1);

    await tapAcross(tester, 0.1);
    expect(current(), 2);
    await tapAcross(tester, 0.9);
    expect(current(), 1);
    expect(taps, 0);
  });

  testWidgets('switching the direction keeps the page', (tester) async {
    await showTurner(tester);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(current(), 1);

    await showTurner(tester, rightToLeft: true);
    await tester.pumpAndSettle();

    expect(find.text('box 1'), findsOneWidget);
    expect(turns, [1], reason: 'no turn');
    expect(across(tester, 2), lessThan(across(tester, 1)));
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(current(), 2);
  });

  testWidgets(
    'a zoomed page still turns by a tap on its edge, at normal size',
    (tester) async {
      await showTurner(tester);
      final zoom = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      zoom.value = Matrix4.diagonal3Values(2, 2, 1);
      await tester.pump();

      await tapAcross(tester, 0.9);

      expect(current(), 1);
      expect(zoom.value.getMaxScaleOnAxis(), 1);
    },
  );

  testWidgets(
    'in a language written right to left, the pages still run by the mode alone',
    (tester) async {
      await showTurner(tester, textDirection: TextDirection.rtl);
      expect(across(tester, 1), greaterThan(across(tester, 0)));

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(
        current(),
        1,
        reason: 'left to right, a swipe to the left goes on',
      );

      await showTurner(
        tester,
        rightToLeft: true,
        textDirection: TextDirection.rtl,
      );
      await tester.pumpAndSettle();
      expect(across(tester, 2), lessThan(across(tester, 1)));
    },
  );

  testWidgets('opens on the page it is given', (tester) async {
    await pumpScreen(
      tester,
      catalog: english,
      screen: Scaffold(
        body: PageTurner(
          count: 3,
          initialIndex: 2,
          onPageChanged: turns.add,
          pageBuilder: (context, index, decodeWidth) =>
              Center(child: Text('box $index')),
        ),
      ),
    );

    expect(find.text('box 2'), findsOneWidget);
    expect(turns, isEmpty);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(turns, isEmpty, reason: 'nothing after the last page');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(current(), 1);
  });

  testWidgets(
    'a zoom step shows the page on screen at once, and every page a turn lands on',
    (tester) async {
      await showTurner(tester, pageShape: shapeOf);

      turner(tester).zoomTo(ZoomStep.fitWidth);
      await tester.pump();
      expect(zoom(tester), zoomOf(ZoomStep.fitWidth, 2 / 3, window(tester)));

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(current(), 1);
      expect(
        zoom(tester),
        Matrix4.identity(),
        reason: 'the spread fitted whole is already as wide as the window',
      );

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(current(), 2);
      expect(zoom(tester), zoomOf(ZoomStep.fitWidth, 2 / 3, window(tester)));

      turner(tester).turnTo(0);
      await tester.pumpAndSettle();
      expect(zoom(tester), zoomOf(ZoomStep.fitWidth, 2 / 3, window(tester)));
    },
  );

  testWidgets('a swipe lands on the next page at the zoom step', (
    tester,
  ) async {
    await showTurner(tester, pageShape: shapeOf);
    turner(tester).turnTo(1);
    turner(tester).zoomTo(ZoomStep.fitWidth);
    await tester.pumpAndSettle();
    expect(
      zoom(tester),
      Matrix4.identity(),
      reason: 'the spread fitted whole, which a swipe can leave',
    );

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(current(), 2);
    expect(zoom(tester), zoomOf(ZoomStep.fitWidth, 2 / 3, window(tester)));
  });

  testWidgets('a turner opens at the zoom step it is given', (tester) async {
    await showTurner(tester, pageShape: shapeOf, initialZoom: ZoomStep.x200);
    await tester.pump();

    expect(zoom(tester), zoomOf(ZoomStep.x200, 2 / 3, window(tester)));
  });

  testWidgets(
    'a pinch is reported and the next turn undoes it; a drag on a zoomed page is no pinch',
    (tester) async {
      await showTurner(tester, pageShape: shapeOf);
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final controller = viewer.transformationController!;

      viewer.onInteractionStart!(ScaleStartDetails());
      controller.value = Matrix4.diagonal3Values(2, 2, 1);
      viewer.onInteractionEnd!(ScaleEndDetails());
      expect(pinches, 1);

      viewer.onInteractionStart!(ScaleStartDetails());
      controller.value = Matrix4.diagonal3Values(2, 2, 1)
        ..setTranslationRaw(-100, -50, 0);
      viewer.onInteractionEnd!(ScaleEndDetails());
      expect(pinches, 1, reason: 'the same scale, moved');

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(zoom(tester), Matrix4.identity());
    },
  );

  testWidgets('a real pinch on a page zooms it and is reported', (
    tester,
  ) async {
    await showTurner(tester);
    final middle = tester.getCenter(find.byType(PageView));

    // Apart up and down, so no sideways swipe takes the gesture.
    final top = await tester.startGesture(middle - const Offset(0, 40));
    final bottom = await tester.startGesture(middle + const Offset(0, 40));
    await tester.pump();
    await top.moveBy(const Offset(0, -60));
    await bottom.moveBy(const Offset(0, 60));
    await tester.pump();
    await top.up();
    await bottom.up();
    await tester.pumpAndSettle();

    expect(zoom(tester).getMaxScaleOnAxis(), greaterThan(1.01));
    expect(pinches, 1);
    expect(turns, isEmpty);
  });

  // Page 0, 2:3, fitted whole in the test window, 800 × 600.
  const fittedPage = Rect.fromLTWH(200, 0, 400, 600);

  testWidgets(
    'a gesture that would move a zoomed page past its edges stops it there',
    (tester) async {
      await showTurner(tester, pageShape: shapeOf);
      final controller = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;

      controller.value = Matrix4.diagonal3Values(3, 3, 1)
        ..setTranslationRaw(500, 400, 0);
      expect(
        MatrixUtils.transformRect(controller.value, fittedPage),
        const Rect.fromLTWH(0, 0, 1200, 1800),
      );

      controller.value = Matrix4.diagonal3Values(3, 3, 1)
        ..setTranslationRaw(-5000, -5000, 0);
      expect(
        MatrixUtils.transformRect(controller.value, fittedPage),
        const Rect.fromLTWH(-400, -1200, 1200, 1800),
      );
    },
  );

  testWidgets(
    'at fit width a sideways drag moves the page no way and turns nothing',
    (tester) async {
      await showTurner(tester, pageShape: shapeOf);
      turner(tester).zoomTo(ZoomStep.fitWidth);
      await tester.pump();

      for (final by in [const Offset(300, 0), const Offset(-300, 0)]) {
        await tester.drag(find.byType(PageView), by);
        await tester.pumpAndSettle();

        final shown = MatrixUtils.transformRect(zoom(tester), fittedPage);
        expect(shown.left, moreOrLessEquals(0), reason: '$by');
        expect(shown.right, moreOrLessEquals(800), reason: '$by');
      }
      expect(turns, isEmpty);
    },
  );

  testWidgets('pinching reaches 4×, past the largest step', (tester) async {
    await showTurner(tester);

    expect(
      tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).maxScale,
      4,
    );
  });

  testWidgets('a step that depends on the window follows it when it changes', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await showTurner(tester, pageShape: shapeOf);
    turner(tester).zoomTo(ZoomStep.fitWidth);
    await tester.pump();

    tester.view.physicalSize = const Size(1500, 1800);
    await tester.pump();
    await tester.pump();

    expect(window(tester), const Size(500, 600));
    expect(zoom(tester), zoomOf(ZoomStep.fitWidth, 2 / 3, window(tester)));
  });

  testWidgets('a page wider than the window starts on the side reading starts, and moves there when the '
      'direction changes', (tester) async {
    await showTurner(tester, pageShape: shapeOf);
    turner(tester).zoomTo(ZoomStep.x300);
    await tester.pump();
    expect(zoom(tester), zoomOf(ZoomStep.x300, 2 / 3, window(tester)));

    await showTurner(tester, pageShape: shapeOf, rightToLeft: true);
    await tester.pump();

    expect(
      zoom(tester),
      zoomOf(ZoomStep.x300, 2 / 3, window(tester), rightToLeft: true),
    );
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
