import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/cover_grid.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });

  final cards = find.byType(CoverCard);

  /// Shows [count] cards named by [nameOf], with the detail [detailOf] gives if any, in a grid
  /// [width] wide, its text at [textScale] times the normal size; answers the indexes of the cards
  /// tapped, in order.
  Future<List<int>> showGrid(
    WidgetTester tester, {
    required double width,
    int count = 6,
    String Function(int index)? nameOf,
    String Function(int index)? detailOf,
    double textScale = 1,
  }) async {
    final taps = <int>[];
    await pumpScreen(
      tester,
      catalog: english,
      screen: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: CoverGrid(
                  itemCount: count,
                  withDetail: detailOf != null,
                  itemBuilder: (context, index) => CoverCard(
                    cover: const AspectRatio(
                      aspectRatio: Covers.aspectRatio,
                      child: Placeholder(),
                    ),
                    name: nameOf?.call(index) ?? 'card $index',
                    detail: detailOf?.call(index),
                    onTap: () => taps.add(index),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return taps;
  }

  testWidgets(
    'fits as many columns as the width takes, none wider than a card gets',
    (tester) async {
      // Width, columns: the grid keeps a gap of Spacing.medium around and between cards.
      for (final (width, columns) in [(800.0, 4), (400.0, 2), (150.0, 1)]) {
        await showGrid(tester, width: width);

        final firstRow = cards.evaluate().where(
          (card) =>
              tester.getTopLeft(find.byWidget(card.widget)).dy ==
              tester.getTopLeft(cards.first).dy,
        );
        final cardWidth = tester.getSize(cards.first).width;
        expect(firstRow, hasLength(columns), reason: 'at $width');
        expect(cardWidth, lessThanOrEqualTo(Covers.maxTileWidth));
        expect(
          columns * cardWidth + (columns + 1) * Spacing.medium,
          moreOrLessEquals(width),
          reason: 'the cards fill the width at $width',
        );
      }
    },
  );

  testWidgets(
    'a long name at twice the text size gets two whole lines under its cover',
    (tester) async {
      const long =
          'a name far too long for two lines under a cover this narrow';
      await showGrid(
        tester,
        width: 400,
        count: 2,
        nameOf: (_) => long,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      final name = tester.renderObject<RenderParagraph>(find.text(long).first);
      expect(name.didExceedMaxLines, isTrue, reason: 'cut after two lines');
      expect(
        name.textSize.height,
        lessThanOrEqualTo(name.size.height),
        reason: 'both lines fit the room the card leaves for its name',
      );
      final cover = tester.getSize(find.byType(Placeholder).first);
      expect(cover.height, moreOrLessEquals(cover.width / Covers.aspectRatio));
    },
  );

  testWidgets('a detail sits right under the name, in one more line of card', (
    tester,
  ) async {
    await showGrid(tester, width: 400, count: 2);
    final plainHeight = tester.getSize(cards.first).height;

    await showGrid(tester, width: 400, count: 2, detailOf: (i) => '$i series');

    final name = find.text('card 0');
    final detail = find.text('0 series');
    expect(
      tester.getTopLeft(detail),
      tester.getBottomLeft(name),
      reason: 'under a one-line name, not at the bottom of the card',
    );
    expect(
      tester.getSize(cards.first).height - plainHeight,
      moreOrLessEquals(tester.getSize(detail).height),
    );
  });

  testWidgets(
    'a long name and its detail at twice the text size both fit their card',
    (tester) async {
      const long =
          'a name far too long for two lines under a cover this narrow';
      await showGrid(
        tester,
        width: 400,
        count: 2,
        nameOf: (_) => long,
        detailOf: (_) => '12 series',
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      final name = tester.renderObject<RenderParagraph>(find.text(long).first);
      expect(name.didExceedMaxLines, isTrue, reason: 'cut after two lines');
      expect(name.textSize.height, lessThanOrEqualTo(name.size.height));
      final detail = find.text('12 series').first;
      expect(
        tester.getBottomLeft(detail).dy,
        lessThanOrEqualTo(tester.getBottomLeft(cards.first).dy),
        reason: 'the detail stays inside its card',
      );
    },
  );

  testWidgets('a card with a detail is one button, named by both', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await showGrid(tester, width: 400, count: 1, detailOf: (_) => '3 series');

    expect(
      tester.getSemantics(cards),
      isSemantics(
        label: 'card 0\n3 series',
        isButton: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('a card is one button, named by its name', (tester) async {
    final semantics = tester.ensureSemantics();
    await showGrid(tester, width: 400, count: 1);

    expect(
      tester.getSemantics(cards),
      isSemantics(label: 'card 0', isButton: true, hasTapAction: true),
    );
    semantics.dispose();
  });

  testWidgets('a tap on the cover or on the name opens the card', (
    tester,
  ) async {
    final taps = await showGrid(tester, width: 400, count: 2);

    await tester.tapAt(tester.getCenter(find.byType(Placeholder).at(1)));
    await tester.tapAt(tester.getCenter(find.text('card 0')));

    expect(taps, [1, 0]);
  });

  testWidgets('a card without a tap is a button that says it is disabled', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpScreen(
      tester,
      catalog: english,
      screen: const Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 120,
            height: 240,
            child: CoverCard(
              cover: AspectRatio(
                aspectRatio: Covers.aspectRatio,
                child: Placeholder(),
              ),
              name: 'card 0',
              onTap: null,
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(cards),
      isSemantics(
        label: 'card 0',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        hasTapAction: false,
      ),
    );
    semantics.dispose();
  });

  /// Shows one card in a grid 400 wide, read as far as [progress] or [finished], whose long press
  /// calls [onLongPress].
  Future<void> showCard(
    WidgetTester tester, {
    double? progress,
    bool finished = false,
    VoidCallback? onLongPress,
  }) => pumpScreen(
    tester,
    catalog: english,
    screen: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          child: CoverGrid(
            itemCount: 1,
            itemBuilder: (context, index) => CoverCard(
              cover: const AspectRatio(
                aspectRatio: Covers.aspectRatio,
                child: Placeholder(),
              ),
              name: 'card 0',
              onTap: () {},
              progress: progress,
              finished: finished,
              onLongPress: onLongPress,
            ),
          ),
        ),
      ),
    ),
  );

  final bar = find.byType(LinearProgressIndicator);
  final check = find.byIcon(Icons.check_circle);

  testWidgets('how far a card was read is a bar along its cover\'s bottom', (
    tester,
  ) async {
    await showCard(tester);
    final plainHeight = tester.getSize(cards).height;
    expect(bar, findsNothing);
    expect(check, findsNothing);

    await showCard(tester, progress: 0.4);

    expect(tester.widget<LinearProgressIndicator>(bar).value, 0.4);
    final cover = find.byType(Placeholder);
    expect(tester.getBottomLeft(bar), tester.getBottomLeft(cover));
    expect(tester.getSize(bar).width, tester.getSize(cover).width);
    expect(check, findsNothing);
    expect(
      tester.getSize(cards).height,
      plainHeight,
      reason: 'the card keeps its height',
    );
  });

  testWidgets('a finished card shows a check in place of its bar', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await showCard(tester, progress: 0.4, finished: true);

    expect(bar, findsNothing);
    expect(check, findsOneWidget);
    final cover = find.byType(Placeholder);
    expect(
      tester.getRect(cover).contains(tester.getCenter(check)),
      isTrue,
      reason: 'on the cover',
    );
    expect(
      tester.getSemantics(cards),
      isSemantics(
        label: '${english.text('browse.finished')}\ncard 0',
        isButton: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('a long press and a right click both do the card\'s long press', (
    tester,
  ) async {
    var pressed = 0;
    await showCard(tester, onLongPress: () => pressed++);

    await tester.longPress(cards);
    await tester.tap(cards, buttons: kSecondaryButton);

    expect(pressed, 2);
  });
}
