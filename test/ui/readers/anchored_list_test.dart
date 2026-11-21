import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/readers/anchored_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });

  final list = GlobalKey<AnchoredListState>();

  /// Shows an [AnchoredList] in the test window, 800 × 600, with [padding] left for the reader's
  /// bars: [count] items saying their index, each [heightOf] tall — 100 by default — and guessed
  /// 100. Answers every item built.
  Future<Set<int>> showList(
    WidgetTester tester, {
    int count = 1000,
    int initialItem = 0,
    EdgeInsets padding = EdgeInsets.zero,
    double Function(int index)? heightOf,
  }) async {
    final built = <int>{};
    await pumpScreen(
      tester,
      catalog: english,
      screen: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(padding: padding),
          child: Material(
            child: AnchoredList(
              key: list,
              count: count,
              initialItem: initialItem,
              guessedHeights: List.filled(count, 100),
              itemBuilder: (context, index) {
                built.add(index);
                return SizedBox(
                  height: heightOf?.call(index) ?? 100,
                  child: Text('item $index'),
                );
              },
            ),
          ),
        ),
      ),
    );
    return built;
  }

  double topOf(WidgetTester tester, int index) =>
      tester.getTopLeft(find.text('item $index')).dy;

  ScrollPosition position(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable)).position;

  Future<void> scrollTo(WidgetTester tester, double offset) async {
    position(tester).jumpTo(offset);
    await tester.pump();
  }

  testWidgets(
    'opens with the item it is given at the top, building only the items near it',
    (tester) async {
      final built = await showList(tester, initialItem: 500);

      expect(topOf(tester, 500), 0);
      expect(built, contains(500));
      expect(
        built.every((index) => index > 480 && index < 520),
        isTrue,
        reason: '$built',
      );
    },
  );

  testWidgets('scrolling up from there shows the items before it, in order', (
    tester,
  ) async {
    await showList(tester, initialItem: 500);

    await scrollTo(tester, -150);

    expect(topOf(tester, 500), 150);
    expect(topOf(tester, 499), 50);
    expect(topOf(tester, 498), -50);
  });

  testWidgets(
    'items above that turn out taller than guessed leave the item being read in place',
    (tester) async {
      await showList(
        tester,
        initialItem: 500,
        heightOf: (index) => index < 500 ? 150 : 100,
      );

      await scrollTo(tester, -300);

      expect(topOf(tester, 500), 300);
      expect(topOf(tester, 499), 150);
    },
  );

  testWidgets('the list is as long as its guesses, wherever it opens', (
    tester,
  ) async {
    await showList(tester);

    for (final item in [0, 500, 990]) {
      list.currentState!.showItem(item);
      await tester.pump();

      final scrolled = position(tester);
      expect(
        scrolled.maxScrollExtent - scrolled.minScrollExtent,
        1000 * 100 - 600,
        reason: 'showing item $item',
      );
    }
  });

  testWidgets(
    'the item on top is the first one reaching below the bar, as the list scrolls',
    (tester) async {
      await showList(
        tester,
        initialItem: 500,
        padding: const EdgeInsets.only(top: 56),
      );
      expect(topOf(tester, 500), 56);
      expect(list.currentState!.topItem, 500);

      // Item 501 then ends 6 below the window's top, 50 above the bar's edge.
      await scrollTo(tester, 250);
      expect(list.currentState!.topItem, 502);

      await scrollTo(tester, -30);
      expect(list.currentState!.topItem, 499);
    },
  );

  testWidgets(
    'shows any item at the top, also the one on top before, and nothing out of range',
    (tester) async {
      await showList(tester, padding: const EdgeInsets.only(top: 56));

      list.currentState!.showItem(42);
      await tester.pump();
      expect(topOf(tester, 42), 56);

      await scrollTo(tester, 1000);
      list.currentState!.showItem(42);
      await tester.pump();
      expect(
        topOf(tester, 42),
        56,
        reason: 'the same item, scrolled away from',
      );

      list.currentState!
        ..showItem(-1)
        ..showItem(1000);
      await tester.pump();
      expect(topOf(tester, 42), 56);
    },
  );

  testWidgets("the first item opens below the bar, with nothing to scroll to above it; the last ends above "
      'the bottom bar', (tester) async {
    await showList(
      tester,
      count: 20,
      padding: const EdgeInsets.only(top: 56, bottom: 56),
    );

    expect(topOf(tester, 0), 56);
    expect(position(tester).minScrollExtent, 0);

    await scrollTo(tester, position(tester).maxScrollExtent);
    expect(tester.getBottomLeft(find.text('item 19')).dy, 600 - 56);
  });
}
