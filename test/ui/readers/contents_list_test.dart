import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/readers/contents_list.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });

  test(
    'the rows list each entry, then the ones beneath it, one level deeper',
    () {
      const tree = [
        _Node('Part One', [
          _Node('Chapter 1', [_Node('Scene 1')]),
          _Node('Chapter 2'),
        ]),
        _Node('Index'),
      ];

      final rows = contentsRows(
        tree,
        titleOf: (node) => node.title,
        childrenOf: (node) => node.children,
        goOf: (node) => node.title == 'Index' ? null : () {},
      );

      expect(
        [for (final row in rows) (row.title, row.depth, row.go != null)],
        [
          ('Part One', 0, true),
          ('Chapter 1', 1, true),
          ('Scene 1', 2, true),
          ('Chapter 2', 1, true),
          ('Index', 0, false),
        ],
      );
    },
  );

  testWidgets('the contents open in a sheet, indented by depth; a row goes there and closes the sheet, one '
      'going nowhere does nothing', (tester) async {
    final went = <String>[];
    await pumpScreen(
      tester,
      catalog: english,
      screen: Scaffold(
        appBar: AppBar(
          actions: [
            ContentsButton(
              rows: [
                (title: 'Part One', depth: 0, go: () => went.add('Part One')),
                (title: 'Chapter 1', depth: 1, go: () => went.add('Chapter 1')),
                (title: 'A heading', depth: 0, go: null),
              ],
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byTooltip(english.text('reader.contents')));
    await tester.pumpAndSettle();
    expect(find.text(english.text('reader.contents')), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Chapter 1')).dx -
          tester.getTopLeft(find.text('Part One')).dx,
      Spacing.large,
    );

    await tester.tap(find.text('A heading'));
    await tester.pumpAndSettle();
    expect(went, isEmpty);
    expect(find.text('A heading'), findsOneWidget, reason: 'the sheet stays');

    await tester.tap(find.text('Chapter 1'));
    await tester.pumpAndSettle();
    expect(went, ['Chapter 1']);
    expect(find.text('Chapter 1'), findsNothing, reason: 'the sheet closed');
  });
}

class _Node {
  const _Node(this.title, [this.children = const []]);

  final String title;
  final List<_Node> children;
}
