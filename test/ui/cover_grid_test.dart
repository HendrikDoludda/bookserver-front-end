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

  /// Shows [count] cards named by [nameOf] in a grid [width] wide, its text at [textScale] times
  /// the normal size; answers the indexes of the cards tapped, in order.
  Future<List<int>> showGrid(
    WidgetTester tester, {
    required double width,
    int count = 6,
    String Function(int index)? nameOf,
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
                  itemBuilder: (context, index) => CoverCard(
                    cover: const AspectRatio(
                      aspectRatio: Covers.aspectRatio,
                      child: Placeholder(),
                    ),
                    name: nameOf?.call(index) ?? 'card $index',
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
