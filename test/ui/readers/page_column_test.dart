import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/readers/page_column.dart';
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

  /// The pages the column said came to the middle of the screen, in order.
  final changes = <int>[];
  var taps = 0;
  setUp(() {
    changes.clear();
    taps = 0;
  });

  // In the test window, 800 × 600, such a page is 1200 tall.
  const portrait = Size(1200, 1800);
  const spread = Size(2400, 1800);

  /// Shows a [PageColumn] of plain boxes at [sizes], each saying its index; answers every build of
  /// a page as its index and the decode width it was given, in order.
  Future<List<(int, int)>> showColumn(
    WidgetTester tester,
    List<Size?> sizes, {
    int initialIndex = 0,
  }) async {
    final builds = <(int, int)>[];
    await pumpScreen(
      tester,
      catalog: english,
      screen: Scaffold(
        body: PageColumn(
          sizes: sizes,
          initialIndex: initialIndex,
          onPageChanged: changes.add,
          onTap: () => taps++,
          pageBuilder: (context, index, decodeWidth) {
            builds.add((index, decodeWidth));
            return SizedBox.expand(
              key: ValueKey('page $index'),
              child: Center(child: Text('box $index')),
            );
          },
        ),
      ),
    );
    return builds;
  }

  Rect page(WidgetTester tester, int index) =>
      tester.getRect(find.byKey(ValueKey('page $index')));

  ScrollPosition position(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable)).position;

  test(
    'a page takes its listed shape, else the last one before it, else 2:3',
    () {
      expect(pageShapes([null, portrait, null, spread, null]), [
        2 / 3,
        2 / 3,
        2 / 3,
        4 / 3,
        4 / 3,
      ]);
    },
  );

  testWidgets(
    'lays every page out as wide as the column at its shape, before anything loads',
    (tester) async {
      await showColumn(tester, [portrait, spread, null]);

      expect(page(tester, 0), const Rect.fromLTWH(0, 0, 800, 1200));
      // A page 1200 tall, the spread and the page after it 600 each, under a window 600 tall.
      expect(position(tester).maxScrollExtent, 1200 + 600 + 600 - 600);
    },
  );

  testWidgets('opens with the page it is given at the top', (tester) async {
    await showColumn(tester, [portrait, portrait, portrait], initialIndex: 2);

    expect(page(tester, 2).top, 0);
    expect(changes, isEmpty);
  });

  testWidgets('reports the page in the middle of the screen as it scrolls', (
    tester,
  ) async {
    await showColumn(tester, [portrait, portrait, portrait]);

    // The middle of the window is 300 below the top of what it shows; the pages start at 0, 1200
    // and 2400.
    for (final offset in [1000.0, 2200.0, 1000.0, 950.0, 800.0]) {
      position(tester).jumpTo(offset);
      await tester.pump();
    }

    expect(changes, [1, 2, 1, 0], reason: 'one report per page that comes');
  });

  testWidgets('a tap is reported, a scroll is not', (tester) async {
    await showColumn(tester, [portrait, portrait]);

    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();
    expect(taps, 1);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets(
    "decodes pages at the page turner's width, kept when the phone turns",
    (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final builds = await showColumn(tester, [portrait, portrait, portrait]);

      tester.view.physicalSize = const Size(2532, 1170);
      await tester.pumpAndSettle();
      position(tester).jumpTo(position(tester).maxScrollExtent);
      await tester.pump();

      expect({for (final (index, _) in builds) index}, contains(2));
      expect({for (final (_, width) in builds) width}, {2340});
    },
  );

  testWidgets(
    'keeps the same page at the top when the window gets narrower or wider',
    (tester) async {
      addTearDown(tester.view.reset);
      await showColumn(tester, [portrait, portrait, portrait], initialIndex: 1);

      for (final (width, height) in [(400.0, 600.0), (1000.0, 1500.0)]) {
        tester.view.physicalSize = Size(width * 3, 600 * 3);
        await tester.pump();

        expect(page(tester, 1).top, moreOrLessEquals(0), reason: '$width');
        expect(page(tester, 1).height, height, reason: '$width');
      }
      expect(changes, isEmpty);
    },
  );

  testWidgets('the arrow keys, the page keys and space scroll it', (
    tester,
  ) async {
    await showColumn(tester, [portrait, portrait, portrait]);

    Future<double> after(LogicalKeyboardKey key, {bool shift = false}) async {
      if (shift) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      }
      await tester.sendKeyEvent(key);
      if (shift) {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      }
      await tester.pumpAndSettle();
      return position(tester).pixels;
    }

    // A tenth of the window per arrow, nine tenths per page key or space.
    expect(await after(LogicalKeyboardKey.arrowDown), moreOrLessEquals(60));
    expect(await after(LogicalKeyboardKey.pageDown), moreOrLessEquals(600));
    expect(await after(LogicalKeyboardKey.space), moreOrLessEquals(1140));
    expect(
      await after(LogicalKeyboardKey.space, shift: true),
      moreOrLessEquals(600),
    );
    expect(await after(LogicalKeyboardKey.arrowUp), moreOrLessEquals(540));
    expect(await after(LogicalKeyboardKey.pageUp), moreOrLessEquals(0));
  });
}
