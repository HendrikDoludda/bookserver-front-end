import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/cover_grid.dart';
import 'package:bookserver/ui/theme.dart';
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
}
