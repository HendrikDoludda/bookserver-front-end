import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/recovery_codes_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });

  const codes = ['AAAA-BBBB-CCCC-DDDD', 'EEEE-FFFF-GGGG-HHHH'];

  /// A first screen that opens the codes screen, as the setup does.
  Future<void> openCodes(WidgetTester tester) async {
    await tester.pumpWidget(
      CatalogScope(
        catalog: english,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RecoveryCodesScreen(codes: codes),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows every code, and no Back', (tester) async {
    await openCodes(tester);

    expect(find.text(english.text('two_factor.codes_title')), findsOneWidget);
    expect(find.text(codes.join('\n')), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('copies all codes, one per line', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await openCodes(tester);

    await tester.tap(find.text(english.text('two_factor.copy_all')));
    await tester.pumpAndSettle();

    expect(copied, 'AAAA-BBBB-CCCC-DDDD\nEEEE-FFFF-GGGG-HHHH');
    expect(find.text(english.text('two_factor.copied')), findsOneWidget);
  });

  testWidgets("the system's Back doesn't leave; Done does", (tester) async {
    await openCodes(tester);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(RecoveryCodesScreen), findsOneWidget);

    await tester.tap(find.text(english.text('two_factor.done')));
    await tester.pumpAndSettle();
    expect(find.byType(RecoveryCodesScreen), findsNothing);
  });
}
