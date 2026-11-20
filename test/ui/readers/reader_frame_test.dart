import 'package:bookserver/data/preferences.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/readers/page_turner.dart';
import 'package:bookserver/ui/readers/reader_frame.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/memory_preferences_store.dart';
import '../../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });

  void onPlatform(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  }

  var controlTaps = 0;
  setUp(() => controlTaps = 0);
  final control = IconButton(
    tooltip: 'Control',
    icon: const Icon(Icons.star),
    onPressed: () => controlTaps++,
  );

  /// Opens a frame around [body] over a first screen, as a book opens over its series; in
  /// [textDirection] when one is given.
  Future<void> openFrame(
    WidgetTester tester, {
    required Widget body,
    List<Widget> controls = const [],
    Widget? status,
    PreferencesController? preferences,
    TextDirection? textDirection,
  }) async {
    await pumpScreen(
      tester,
      catalog: english,
      preferences: preferences,
      screen: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) {
                    final frame = ReaderFrame(
                      title: 'A Book',
                      controls: controls,
                      status: status,
                      body: body,
                    );
                    return textDirection == null
                        ? frame
                        : Directionality(
                            textDirection: textDirection,
                            child: frame,
                          );
                  },
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

  ReaderFrameState frame(WidgetTester tester) =>
      tester.state<ReaderFrameState>(find.byType(ReaderFrame));

  Finder inTopBar(Finder finder) =>
      find.descendant(of: find.byType(AppBar), matching: finder);

  final pages = PageView(
    children: [
      for (final page in ['one', 'two']) Center(child: Text(page)),
    ],
  );

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets(
      'on ${platform.name} Back, the title and the controls share the top bar',
      (tester) async {
        onPlatform(platform);
        await openFrame(tester, body: pages, controls: [control]);

        expect(inTopBar(find.byType(BackButton)), findsOneWidget);
        expect(inTopBar(find.text('A Book')), findsOneWidget);
        expect(inTopBar(find.byTooltip('Control')), findsOneWidget);
      },
    );
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('on ${platform.name} the controls sit in a bar at the bottom', (
      tester,
    ) async {
      onPlatform(platform);
      await openFrame(tester, body: pages, controls: [control]);

      expect(inTopBar(find.byType(BackButton)), findsOneWidget);
      expect(inTopBar(find.text('A Book')), findsOneWidget);
      expect(inTopBar(find.byTooltip('Control')), findsNothing);
      final screen = tester.getSize(find.byType(ReaderFrame));
      final button = tester.getCenter(find.byTooltip('Control'));
      expect(button.dy, greaterThan(screen.height / 2));
      expect(
        button.dx,
        greaterThan(screen.width / 2),
        reason: 'at the right-hand end until the handedness says otherwise',
      );
    });
  }

  Future<PreferencesController> leftHanded() async {
    final preferences = PreferencesController(store: MemoryPreferencesStore());
    await preferences.setHandedness(Handedness.left);
    return preferences;
  }

  testWidgets(
    "left-handed, the bottom bar's controls gather at its left end; a change shows at once",
    (tester) async {
      onPlatform(TargetPlatform.android);
      final preferences = await leftHanded();
      await openFrame(
        tester,
        body: pages,
        controls: [control],
        preferences: preferences,
      );
      final width = tester.getSize(find.byType(ReaderFrame)).width;

      expect(
        tester.getCenter(find.byTooltip('Control')).dx,
        lessThan(width / 2),
      );

      await preferences.setHandedness(Handedness.right);
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byTooltip('Control')).dx,
        greaterThan(width / 2),
      );
    },
  );

  testWidgets(
    "the thumb's side is the physical one in a right-to-left language",
    (tester) async {
      onPlatform(TargetPlatform.iOS);
      await openFrame(
        tester,
        body: pages,
        controls: [control],
        preferences: await leftHanded(),
        textDirection: TextDirection.rtl,
      );

      expect(
        tester.getCenter(find.byTooltip('Control')).dx,
        lessThan(tester.getSize(find.byType(ReaderFrame)).width / 2),
      );
    },
  );

  testWidgets('on a desktop the hand moves nothing', (tester) async {
    onPlatform(TargetPlatform.macOS);
    await openFrame(
      tester,
      body: pages,
      controls: [control],
      preferences: await leftHanded(),
    );

    expect(inTopBar(find.byTooltip('Control')), findsOneWidget);
  });

  testWidgets('without controls a phone has no bar at the bottom', (
    tester,
  ) async {
    onPlatform(TargetPlatform.iOS);
    var bodyTaps = 0;
    await openFrame(
      tester,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => bodyTaps++,
      ),
    );

    await tester.tapAt(const Offset(400, 590));

    expect(bodyTaps, 1, reason: 'the bottom of the pages is theirs');
  });

  testWidgets('the bars show when a book opens and hide once its pages move', (
    tester,
  ) async {
    await openFrame(tester, body: pages);
    expect(frame(tester).barShown, isTrue);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(frame(tester).barShown, isFalse);
  });

  testWidgets('scrolling text hides the bars too', (tester) async {
    await openFrame(
      tester,
      body: ListView(
        children: [for (var line = 0; line < 100; line++) Text('line $line')],
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(frame(tester).barShown, isFalse);
  });

  testWidgets('a page that scrolls sideways inside the pages leaves the bars', (
    tester,
  ) async {
    await openFrame(
      tester,
      body: ListView(
        children: [
          SizedBox(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var cell = 0; cell < 50; cell++) Text('cell $cell '),
              ],
            ),
          ),
        ],
      ),
    );

    await tester.drag(find.text('cell 0 '), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(frame(tester).barShown, isTrue);
  });

  testWidgets('hidden bars slide out of view and take no taps', (tester) async {
    onPlatform(TargetPlatform.iOS);
    await openFrame(tester, body: pages, controls: [control]);
    final backButton = tester.getCenter(find.byType(BackButton));
    final controlButton = tester.getCenter(find.byTooltip('Control'));

    frame(tester).toggleBar();
    await tester.pumpAndSettle();

    expect(frame(tester).barShown, isFalse);
    expect(tester.getBottomLeft(find.byType(AppBar)).dy, lessThanOrEqualTo(0));
    await tester.tapAt(backButton);
    await tester.tapAt(controlButton);
    await tester.pumpAndSettle();
    expect(find.byType(ReaderFrame), findsOneWidget, reason: 'Back was hidden');
    expect(controlTaps, 0);

    frame(tester).toggleBar();
    await tester.pumpAndSettle();
    expect(frame(tester).barShown, isTrue);
    await tester.tap(find.byTooltip('Control'));
    expect(controlTaps, 1);
  });

  testWidgets('the status shows under the pages, with or without the bars', (
    tester,
  ) async {
    await openFrame(tester, body: pages, status: const Text('Page 1 of 2'));
    final status = find.text('Page 1 of 2');
    expect(status, findsOneWidget);
    expect(
      tester.getTopLeft(status).dy,
      greaterThan(tester.getBottomLeft(find.byType(PageView)).dy),
    );

    frame(tester).hideBar();
    await tester.pumpAndSettle();
    expect(status, findsOneWidget);
  });

  testWidgets('Back closes the book', (tester) async {
    await openFrame(tester, body: pages);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(ReaderFrame), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a list in the pages starts below the top bar', (tester) async {
    await openFrame(
      tester,
      body: ListView(
        children: [for (var line = 0; line < 100; line++) Text('line $line')],
      ),
    );

    expect(
      tester.getTopLeft(find.text('line 0')).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.byType(AppBar)).dy),
    );
  });

  testWidgets('the arrow keys still turn the pages after a control was used', (
    tester,
  ) async {
    onPlatform(TargetPlatform.macOS);
    final turns = <int>[];
    await openFrame(
      tester,
      body: PageTurner(
        count: 3,
        onPageChanged: turns.add,
        pageBuilder: (context, index, decodeWidth) =>
            Center(child: Text('box $index')),
      ),
      controls: [control],
    );

    await tester.tap(find.byTooltip('Control'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(controlTaps, 1);
    expect(turns, [1]);
  });
}
