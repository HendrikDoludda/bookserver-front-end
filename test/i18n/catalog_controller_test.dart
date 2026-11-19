import 'dart:async';

import 'package:bookserver/data/locales_api.dart';
import 'package:bookserver/data/session.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/data/session_store.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/i18n/catalog_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fake_server.dart';
import '../support/memory_session_store.dart';
import '../support/screens.dart';

void main() {
  group('pickLanguage', () {
    OfferedLanguage offer(String code, {bool isDefault = false}) =>
        OfferedLanguage(code: code, isDefault: isDefault);
    final englishAndGerman = [offer('en', isDefault: true), offer('de')];

    test("the user's setting while the server offers it", () {
      expect(
        pickLanguage(
          englishAndGerman,
          setting: 'de',
          device: const [Locale('en')],
        ),
        'de',
      );
      expect(
        pickLanguage(
          englishAndGerman,
          setting: 'fr',
          device: const [Locale('de')],
        ),
        'de',
        reason: 'a setting the server no longer offers: the device decides',
      );
    });

    test('else the first device language the server offers', () {
      expect(
        pickLanguage(
          englishAndGerman,
          device: const [Locale('fr', 'FR'), Locale('de', 'DE')],
        ),
        'de',
      );
    });

    test('a device language matches its region, else its language, else a code of that language', () {
      expect(
        pickLanguage(
          [offer('en', isDefault: true), offer('pt-PT'), offer('pt-BR')],
          device: const [Locale('pt', 'BR')],
        ),
        'pt-BR',
      );
      expect(
        pickLanguage(englishAndGerman, device: const [Locale('de', 'AT')]),
        'de',
      );
      expect(
        pickLanguage(
          [offer('en', isDefault: true), offer('pt-BR')],
          device: const [Locale('pt', 'PT')],
        ),
        'pt-BR',
      );
      expect(
        pickLanguage(
          [offer('en', isDefault: true), offer('de-CH')],
          device: const [Locale('de')],
        ),
        'de-CH',
      );
    });

    test("the device's order beats an exact match further down its list", () {
      expect(
        pickLanguage(
          [offer('en', isDefault: true), offer('de-DE'), offer('fr-CH')],
          device: const [Locale('de', 'CH'), Locale('fr', 'CH')],
        ),
        'de-DE',
      );
    });

    test('a region alone is no match', () {
      expect(
        pickLanguage(
          [offer('en', isDefault: true), offer('de-CH')],
          device: const [Locale('fr', 'CH')],
        ),
        'en',
      );
    });

    test("else the server's default, else its first language, else none", () {
      final germanFirst = [offer('de'), offer('en', isDefault: true)];
      expect(pickLanguage(germanFirst, device: const [Locale('fr')]), 'en');
      expect(pickLanguage(germanFirst), 'en', reason: 'no device languages');
      expect(
        pickLanguage([offer('de'), offer('en')], device: const [Locale('fr')]),
        'de',
        reason: 'no default',
      );
      expect(
        pickLanguage(const [], setting: 'de', device: const [Locale('de')]),
        isNull,
      );
    });
  });

  group('CatalogController', () {
    final builtIn = Catalog.fromJson({
      'login': {'title': 'Sign in', 'subtitle': 'Built in'},
    }, language: 'en');

    late _CatalogServer server;
    setUp(() => server = _CatalogServer());

    StoredConnection signedOut() => StoredConnection(server: testOrigin);

    Future<SessionController> sessionOn(SessionStore store) async {
      final session = SessionController(
        store: store,
        client: server.fake.client,
        platform: 'macos',
      );
      await session.load();
      return session;
    }

    CatalogController following(
      SessionController session, {
      List<Locale> device = const [Locale('en')],
    }) {
      final catalogs = CatalogController(
        builtIn: builtIn,
        client: server.fake.client,
        session: session,
        deviceLocales: () => device,
      );
      addTearDown(catalogs.dispose);
      catalogs.load();
      return catalogs;
    }

    test(
      'signed out, it shows the device language the server offers',
      () async {
        final session = await sessionOn(
          MemorySessionStore()..connection = signedOut(),
        );
        final catalogs = following(session, device: const [Locale('de')]);
        expect(
          catalogs.catalog,
          same(builtIn),
          reason: 'nothing waits for the server',
        );

        await pumpEventQueue();

        expect(catalogs.catalog.language, 'de');
        expect(catalogs.catalog.text('login.title'), 'Anmelden');
        expect(server.paths, [
          '/api/v1/locales',
          '/api/v1/locales/de/translations',
        ]);
        for (final request in server.fake.requests) {
          expect(request.headers.containsKey('authorization'), isFalse);
        }
      },
    );

    test(
      "signed in, the user's setting wins over the device's language",
      () async {
        server.setting = 'de';
        final session = await sessionOn(signedInStore());
        final catalogs = following(session, device: const [Locale('en')]);

        await pumpEventQueue();

        expect(catalogs.catalog.language, 'de');
        expect(server.paths, [
          '/api/v1/locales',
          '/api/v1/account/settings',
          '/api/v1/locales/de/translations',
        ]);
        expect(
          server.fake.requests[1].headers['authorization'],
          'Bearer session-1',
        );
      },
    );

    test('signed in without a setting, the device decides', () async {
      final session = await sessionOn(signedInStore());
      final catalogs = following(session, device: const [Locale('de')]);

      await pumpEventQueue();

      expect(catalogs.catalog.language, 'de');
    });

    test('signing in picks again, with the setting', () async {
      server.setting = 'de';
      final session = await sessionOn(
        MemorySessionStore()..connection = signedOut(),
      );
      final catalogs = following(session);
      await pumpEventQueue();
      expect(catalogs.catalog.language, 'en');

      await session.logIn('alice', 'correct horse battery');
      await pumpEventQueue();

      expect(catalogs.catalog.language, 'de');
    });

    test("signing out picks again, without the user's setting", () async {
      server.setting = 'de';
      final session = await sessionOn(signedInStore());
      final catalogs = following(session);
      await pumpEventQueue();
      expect(catalogs.catalog.language, 'de');

      await session.logOut();
      await pumpEventQueue();

      expect(catalogs.catalog.language, 'en');
      expect(catalogs.catalog.text('login.title'), 'Sign in, from the server');
    });

    test('without a server nothing is asked; a new server is', () async {
      final session = await sessionOn(MemorySessionStore());
      final catalogs = following(session, device: const [Locale('de')]);
      await pumpEventQueue();
      expect(server.fake.requests, isEmpty);
      expect(catalogs.catalog, same(builtIn));

      await session.useServer(testAddress);
      await pumpEventQueue();

      expect(catalogs.catalog.language, 'de');
      expect(server.paths, [
        '/health',
        '/api/v1/locales',
        '/api/v1/locales/de/translations',
      ]);
    });

    test('forgetting the server keeps the catalog on screen', () async {
      final session = await sessionOn(
        MemorySessionStore()..connection = signedOut(),
      );
      final catalogs = following(session, device: const [Locale('de')]);
      await pumpEventQueue();
      final requests = server.fake.requests.length;

      await session.forgetServer();
      await pumpEventQueue();

      expect(catalogs.catalog.language, 'de');
      expect(server.fake.requests, hasLength(requests));
    });

    test('the same stage again asks nothing', () async {
      final session = await sessionOn(
        MemorySessionStore()..connection = signedOut(),
      );
      following(session);
      await pumpEventQueue();
      final requests = server.fake.requests.length;

      await session.load();
      await pumpEventQueue();

      expect(server.fake.requests, hasLength(requests));
    });

    test(
      'a failed pick keeps the catalog on screen and notifies nobody',
      () async {
        final failures = <String, Future<http.Response> Function()>{
          'no connection': () async =>
              throw http.ClientException('Connection refused'),
          'a refusal': () async => jsonAnswer({'error': 'internal_error'}, 500),
          'a broken catalog': () async => jsonAnswer({'login': 'no texts'}),
        };
        for (final MapEntry(key: failure, value: answer) in failures.entries) {
          server = _CatalogServer()
            ..answers['/api/v1/locales/de/translations'] = answer;
          final session = await sessionOn(
            MemorySessionStore()..connection = signedOut(),
          );
          final catalogs = following(session, device: const [Locale('de')]);
          var notified = 0;
          catalogs.addListener(() => notified++);

          await pumpEventQueue();

          expect(catalogs.catalog, same(builtIn), reason: failure);
          expect(notified, 0, reason: failure);
        }
      },
    );

    test(
      "a list of languages the server can't give keeps the catalog",
      () async {
        server.answers['/api/v1/locales'] = () async =>
            jsonAnswer({'error': 'not_found'}, 404);
        final session = await sessionOn(
          MemorySessionStore()..connection = signedOut(),
        );
        final catalogs = following(session, device: const [Locale('de')]);

        await pumpEventQueue();

        expect(catalogs.catalog, same(builtIn));
        expect(server.paths, ['/api/v1/locales']);
      },
    );

    test('a new catalog notifies the listeners once', () async {
      final session = await sessionOn(
        MemorySessionStore()..connection = signedOut(),
      );
      final catalogs = following(session, device: const [Locale('de')]);
      var notified = 0;
      catalogs.addListener(() => notified++);

      await pumpEventQueue();

      expect(notified, 1);
    });

    test(
      'an answer that arrives after a newer pick began is dropped',
      () async {
        final slowEnglish = Completer<http.Response>();
        server.answers['/api/v1/locales/en/translations'] = () =>
            slowEnglish.future;
        server.setting = 'de';
        final session = await sessionOn(
          MemorySessionStore()..connection = signedOut(),
        );
        final catalogs = following(session);
        await pumpEventQueue();

        await session.logIn('alice', 'correct horse battery');
        await pumpEventQueue();
        expect(catalogs.catalog.language, 'de');

        slowEnglish.complete(
          jsonAnswer({
            'login': {'title': 'Too late'},
          }),
        );
        await pumpEventQueue();

        expect(catalogs.catalog.language, 'de');
        expect(catalogs.catalog.text('login.title'), 'Anmelden');
      },
    );

    test(
      'a session that ends while picking leads to the signed-out pick',
      () async {
        final refused = jsonAnswer({'error': 'unauthorized'}, 401);
        server
          ..setting = 'de'
          ..answers['/api/v1/account/settings'] = (() async => refused)
          ..answers['/api/v1/auth/refresh'] = (() async => refused);
        final session = await sessionOn(signedInStore());
        final catalogs = following(session);

        await pumpEventQueue();

        expect(session.stage, isA<LoggedOut>());
        expect(catalogs.catalog.language, 'en');
        expect(server.paths, [
          '/api/v1/locales',
          '/api/v1/account/settings',
          '/api/v1/auth/refresh',
          '/api/v1/locales',
          '/api/v1/locales/en/translations',
        ]);
      },
    );

    test(
      "a key the server's catalog lacks shows the built-in English text",
      () async {
        final session = await sessionOn(
          MemorySessionStore()..connection = signedOut(),
        );
        final catalogs = following(session, device: const [Locale('de')]);

        await pumpEventQueue();

        expect(catalogs.catalog.text('login.title'), 'Anmelden');
        expect(catalogs.catalog.text('login.subtitle'), 'Built in');
      },
    );

    test('a pick still on its way when disposed changes nothing', () async {
      final waiting = Completer<http.Response>();
      server.answers['/api/v1/locales/de/translations'] = () => waiting.future;
      final session = await sessionOn(
        MemorySessionStore()..connection = signedOut(),
      );
      final catalogs = CatalogController(
        builtIn: builtIn,
        client: server.fake.client,
        session: session,
        deviceLocales: () => const [Locale('de')],
      )..load();
      await pumpEventQueue();

      catalogs.dispose();
      waiting.complete(
        jsonAnswer({
          'login': {'title': 'Anmelden'},
        }),
      );
      await pumpEventQueue();

      expect(catalogs.catalog, same(builtIn));
    });
  });
}

/// A book server whose catalog offers English, its default, and German, each with its own login
/// title; [setting] is the user's language. [answers] replaces the answer for a path.
class _CatalogServer {
  String? setting;
  final answers = <String, Future<http.Response> Function()>{};

  late final fake = bookServer((request) async {
    if (answers[request.url.path] case final answer?) {
      return answer();
    }
    return switch (request.url.pathSegments) {
      ['api', 'v1', 'locales'] => jsonAnswer([
        {
          'code': 'en',
          'display_name': 'English',
          'icon': null,
          'is_default': true,
        },
        {
          'code': 'de',
          'display_name': 'Deutsch',
          'icon': null,
          'is_default': false,
        },
      ]),
      ['api', 'v1', 'locales', 'en', 'translations'] => jsonAnswer({
        'login': {'title': 'Sign in, from the server'},
      }),
      ['api', 'v1', 'locales', 'de', 'translations'] => jsonAnswer({
        'login': {'title': 'Anmelden'},
      }),
      ['api', 'v1', 'account', 'settings'] => jsonAnswer({'locale': setting}),
      ['api', 'v1', 'auth', 'login'] => jsonAnswer({
        'status': 'ok',
        ...tokensJson(),
      }),
      ['api', 'v1', 'auth', 'logout'] => http.Response('', 204),
      _ => notFound(),
    };
  });

  /// The paths asked for, in order.
  List<String> get paths => [
    for (final request in fake.requests) request.url.path,
  ];
}
