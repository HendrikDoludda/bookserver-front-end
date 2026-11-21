import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/readers/zoom.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });

  // A page 2:3 fitted whole in a window 800 × 600 is 400 × 600, from x 200 on; a page 4:3 in a
  // window 400 × 600 is 400 × 300, from y 150 on.
  const wide = Size(800, 600);
  const tall = Size(400, 600);
  const portrait = (shape: 2 / 3, fitted: Rect.fromLTWH(200, 0, 400, 600));
  const landscape = (shape: 4 / 3, fitted: Rect.fromLTWH(0, 150, 400, 300));

  /// Where [step] puts a page fitted whole as [fitted], of [shape], in [window].
  Rect shown(
    ZoomStep step,
    ({double shape, Rect fitted}) page,
    Size window, {
    bool rightToLeft = false,
  }) => MatrixUtils.transformRect(
    zoomOf(step, page.shape, window, rightToLeft: rightToLeft),
    page.fitted,
  );

  test('fit page shows the page whole, as it already is', () {
    expect(shown(ZoomStep.fitPage, portrait, wide), portrait.fitted);
    expect(shown(ZoomStep.fitPage, landscape, tall), landscape.fitted);
  });

  test("fit width spreads the page across the window, from the page's top", () {
    expect(
      shown(ZoomStep.fitWidth, portrait, wide),
      const Rect.fromLTWH(0, 0, 800, 1200),
    );
    expect(
      shown(ZoomStep.fitWidth, landscape, tall),
      landscape.fitted,
      reason: 'a page already as wide as the window',
    );
  });

  test("a multiple of the whole page starts at the page's top, centred while it is narrower than "
      'the window, else on the side reading starts', () {
    expect(
      shown(ZoomStep.x150, portrait, wide),
      const Rect.fromLTWH(100, 0, 600, 900),
    );
    expect(
      shown(ZoomStep.x200, portrait, wide),
      const Rect.fromLTWH(0, 0, 800, 1200),
    );
    expect(
      shown(ZoomStep.x300, portrait, wide),
      const Rect.fromLTWH(0, 0, 1200, 1800),
    );
    expect(
      shown(ZoomStep.x300, portrait, wide, rightToLeft: true),
      const Rect.fromLTWH(-400, 0, 1200, 1800),
    );
    expect(
      shown(ZoomStep.x200, landscape, tall),
      const Rect.fromLTWH(0, 0, 800, 600),
      reason: 'as tall as the window: centred, so from its top',
    );
    expect(
      shown(ZoomStep.x200, landscape, tall, rightToLeft: true),
      const Rect.fromLTWH(-400, 0, 800, 600),
    );
  });

  test(
    'a window not laid out yet, or a page without a shape, stays as it is',
    () {
      for (final (shape, window) in [
        (2 / 3, Size.zero),
        (0.0, wide),
        (double.nan, wide),
        (double.infinity, wide),
      ]) {
        expect(
          zoomOf(ZoomStep.x300, shape, window),
          Matrix4.identity(),
          reason: '$shape in $window',
        );
      }
    },
  );

  /// Where a page fitted whole as [page] shows under [matrix] once it is kept on screen.
  Rect kept(Matrix4 matrix, ({double shape, Rect fitted}) page, Size window) =>
      MatrixUtils.transformRect(
        keepOnPage(matrix, page.shape, window),
        page.fitted,
      );

  Matrix4 zoomedBy(double scale, double x, double y) =>
      Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(x, y, 0);

  test('a page larger than the window stops at its edges, however far it is dragged', () {
    // At 3×, the portrait page is 1200 × 1800 in a window 800 × 600.
    expect(
      kept(zoomedBy(3, 500, 400), portrait, wide),
      const Rect.fromLTWH(0, 0, 1200, 1800),
      reason: 'dragged right and down, past its top left',
    );
    expect(
      kept(zoomedBy(3, -5000, -5000), portrait, wide),
      const Rect.fromLTWH(-400, -1200, 1200, 1800),
      reason: 'dragged left and up, past its bottom right',
    );
  });

  test(
    'a page smaller than the window, across or down, stays centred that way',
    () {
      // At 1.5×, the portrait page is 600 wide in a window 800 wide.
      expect(
        kept(zoomedBy(1.5, -900, -100), portrait, wide),
        const Rect.fromLTWH(100, -100, 600, 900),
      );
      // At 2×, the landscape page is as tall as the window: it can only move across.
      expect(
        kept(zoomedBy(2, -100, 300), landscape, tall),
        const Rect.fromLTWH(-100, 0, 800, 600),
      );
    },
  );

  test('a page moved within its edges stays where it is', () {
    final matrix = zoomedBy(3, -800, -300);

    expect(keepOnPage(matrix, portrait.shape, wide), same(matrix));
  });

  test('every zoom step keeps its page on screen already', () {
    for (final step in ZoomStep.values) {
      for (final rightToLeft in [false, true]) {
        for (final (page, window) in [(portrait, wide), (landscape, tall)]) {
          final shown = MatrixUtils.transformRect(
            zoomOf(step, page.shape, window, rightToLeft: rightToLeft),
            page.fitted,
          );
          final keptShown = kept(
            zoomOf(step, page.shape, window, rightToLeft: rightToLeft),
            page,
            window,
          );
          final reason = '$step, right to left $rightToLeft, in $window';
          expect(keptShown.left, moreOrLessEquals(shown.left), reason: reason);
          expect(keptShown.top, moreOrLessEquals(shown.top), reason: reason);
        }
      }
    }
  });

  testWidgets(
    'the zoom menu offers every step, the one on screen checked, and none after a pinch',
    (tester) async {
      ZoomStep? chosen;
      Future<void> show(ZoomStep? step) => pumpScreen(
        tester,
        catalog: english,
        screen: Scaffold(
          appBar: AppBar(
            actions: [
              ZoomButton(step: step, onChanged: (step) => chosen = step),
            ],
          ),
        ),
      );
      final entries = find.byWidgetPredicate(
        (widget) => widget is CheckedPopupMenuItem<ZoomStep>,
      );
      List<(ZoomStep?, bool)> checks() => [
        for (final entry in tester.widgetList<CheckedPopupMenuItem<ZoomStep>>(
          entries,
        ))
          (entry.value, entry.checked),
      ];
      Future<void> openMenu() async {
        await tester.tap(find.byTooltip(english.text('reader.zoom')));
        await tester.pumpAndSettle();
      }

      await show(ZoomStep.x150);
      await openMenu();
      expect(checks(), [
        (ZoomStep.fitPage, false),
        (ZoomStep.fitWidth, false),
        (ZoomStep.x150, true),
        (ZoomStep.x200, false),
        (ZoomStep.x300, false),
      ]);
      for (final label in [
        english.text('reader.zoom_fit_page'),
        english.text('reader.zoom_fit_width'),
        for (final percent in [150, 200, 300])
          english.text('reader.percent', {'percent': percent}),
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }

      await tester.tap(
        find.ancestor(
          of: find.text(english.text('reader.percent', {'percent': 300})),
          matching: entries,
        ),
      );
      await tester.pumpAndSettle();
      expect(chosen, ZoomStep.x300);

      await show(null);
      await openMenu();
      expect([
        for (final (_, checked) in checks()) checked,
      ], everyElement(isFalse));
    },
  );
}
