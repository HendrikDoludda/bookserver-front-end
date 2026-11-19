import 'dart:convert';

import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/two_factor_setup_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../support/fake_server.dart';
import '../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });

  const link = 'otpauth://totp/Bookserver:alice?secret=JBSWY3DPEHPK3PXP';

  /// A server whose setup starts with [start] and confirms with [confirm].
  FakeServer setupServer({
    http.Response Function()? start,
    http.Response Function()? confirm,
  }) => bookServer(
    (request) async => switch (request.url.path) {
      '/api/v1/account/totp' =>
        start?.call() ??
            jsonAnswer({
              'otpauth_url': link,
              'secret_base32': 'JBSWY3DPEHPK3PXP',
            }),
      '/api/v1/account/totp/confirm' =>
        confirm?.call() ?? jsonAnswer({'recovery_codes': <String>[]}),
      _ => notFound(),
    },
  );

  /// The setup screen alone, signed in on [server], opening links with [openLink].
  Future<void> atSetup(
    WidgetTester tester,
    FakeServer server, {
    OpenLink? openLink,
  }) async {
    final session = await signedInSession(server);
    await pumpScreen(
      tester,
      catalog: english,
      screen: TwoFactorSetupScreen(
        session: session,
        openLink: openLink ?? (_) async => true,
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder openButton() => find.text(english.text('two_factor.open_in_app'));
  Finder confirmButton() =>
      find.widgetWithText(FilledButton, english.text('two_factor.confirm'));

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  void onPlatform(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  }

  testWidgets('offers to open the link only on phones', (tester) async {
    for (final (platform, offered) in [
      (TargetPlatform.iOS, true),
      (TargetPlatform.android, true),
      (TargetPlatform.macOS, false),
      (TargetPlatform.windows, false),
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(const SizedBox());
      await atSetup(tester, setupServer());

      expect(
        openButton(),
        offered ? findsOneWidget : findsNothing,
        reason: '$platform',
      );
    }
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('opens the otpauth link', (tester) async {
    onPlatform(TargetPlatform.iOS);
    final opened = <Uri>[];
    await atSetup(
      tester,
      setupServer(),
      openLink: (link) async {
        opened.add(link);
        return true;
      },
    );

    await tapAndSettle(tester, openButton());

    expect(opened, [Uri.parse(link)]);
    expect(find.text(english.text('two_factor.no_app')), findsNothing);
  });

  testWidgets('says so when no app takes the link', (tester) async {
    onPlatform(TargetPlatform.android);
    for (final OpenLink openLink in [
      (_) async => false,
      (_) async => throw PlatformException(code: 'ACTIVITY_NOT_FOUND'),
    ]) {
      await tester.pumpWidget(const SizedBox());
      await atSetup(tester, setupServer(), openLink: openLink);

      await tapAndSettle(tester, openButton());

      expect(find.text(english.text('two_factor.no_app')), findsOneWidget);
    }
  });

  testWidgets('copies the setup key', (tester) async {
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
    await atSetup(tester, setupServer());

    await tapAndSettle(tester, find.text(english.text('two_factor.copy')));

    expect(copied, 'JBSWY3DPEHPK3PXP');
    expect(find.text(english.text('two_factor.copied')), findsOneWidget);
  });

  testWidgets('waits for six digits and the password', (tester) async {
    await atSetup(tester, setupServer());
    FilledButton button() => tester.widget<FilledButton>(confirmButton());
    final code = find.widgetWithText(
      TextField,
      english.text('two_factor.code'),
    );
    final password = find.widgetWithText(
      TextField,
      english.text('two_factor.password'),
    );

    await tester.enterText(code, '12a345');
    await tester.enterText(password, 'pw');
    await tester.pump();
    expect(button().onPressed, isNull, reason: 'five digits');

    await tester.enterText(code, '123456');
    await tester.pump();
    expect(button().onPressed, isNotNull);
  });

  testWidgets('a refused confirmation says why and stays', (tester) async {
    final server = setupServer(
      confirm: () => jsonAnswer({'error': 'incorrect_password'}, 400),
    );
    await atSetup(tester, server);

    await tester.enterText(
      find.widgetWithText(TextField, english.text('two_factor.code')),
      '123456',
    );
    await tester.enterText(
      find.widgetWithText(TextField, english.text('two_factor.password')),
      'wrong',
    );
    await tester.pump();
    await tapAndSettle(tester, confirmButton());

    expect(
      find.text(english.text('errors.incorrect_password')),
      findsOneWidget,
    );
    expect(find.byType(TwoFactorSetupScreen), findsOneWidget);
    expect(
      jsonDecode(
        server.requests
            .lastWhere((r) => r.url.path == '/api/v1/account/totp/confirm')
            .body,
      ),
      {'code': '123456', 'password': 'wrong'},
    );
  });

  testWidgets('a setup that failed to start says why, with Reload', (
    tester,
  ) async {
    var starts = 0;
    await atSetup(
      tester,
      setupServer(
        start: () => ++starts == 1
            ? jsonAnswer({'error': 'internal_error'}, 500)
            : jsonAnswer({'otpauth_url': link, 'secret_base32': 'XYZ'}),
      ),
    );

    expect(find.text(english.text('errors.internal_error')), findsOneWidget);
    await tapAndSettle(tester, find.text(english.text('settings.reload')));

    expect(find.text('XYZ'), findsOneWidget);
    expect(find.text(english.text('errors.internal_error')), findsNothing);
  });
}
