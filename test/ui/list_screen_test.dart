import 'dart:async';

import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/list_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });

  /// Shows a list whose every load waits for the next of [answers], and that loads again whenever
  /// [reloads] notifies.
  Future<void> showList(
    WidgetTester tester,
    List<Completer<List<String>>> answers,
    Listenable reloads,
  ) {
    var loads = 0;
    return pumpScreen(
      tester,
      catalog: english,
      screen: ListScreen<String>(
        title: 'Things',
        emptyKey: 'browse.books_empty',
        reloadKey: 'browse.reload',
        reloadOn: reloads,
        load: () => answers[loads++].future,
        builder: (context, items) =>
            ListView(children: [for (final item in items) Text(item)]),
      ),
    );
  }

  testWidgets('a reload keeps the list on screen until the new one is in', (
    tester,
  ) async {
    final answers = List.generate(2, (_) => Completer<List<String>>());
    final reloads = ValueNotifier(0);
    await showList(tester, answers, reloads);
    answers[0].complete(['first']);
    await tester.pump();

    reloads.value++;
    await tester.pump();
    expect(find.text('first'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    answers[1].complete(['second']);
    await tester.pump();
    expect(find.text('second'), findsOneWidget);
    expect(find.text('first'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    reloads.dispose();
  });

  testWidgets('of two reloads, the later one shows, whichever answers last', (
    tester,
  ) async {
    final answers = List.generate(3, (_) => Completer<List<String>>());
    final reloads = ValueNotifier(0);
    await showList(tester, answers, reloads);
    answers[0].complete(['first']);
    await tester.pump();

    reloads.value++;
    reloads.value++;
    await tester.pump();
    answers[2].complete(['newest']);
    await tester.pump();
    answers[1].complete(['out of date']);
    await tester.pump();

    expect(find.text('newest'), findsOneWidget);
    expect(find.text('out of date'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    reloads.dispose();
  });
}
