import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookserver/data/catalog_store.dart';
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
import '../support/memory_catalog_store.dart';
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

    Future<CatalogController> following(
      SessionController session, {
      List<Locale> device = const [Locale('en')],
      CatalogStore? store,
    }) async {
      final catalogs = CatalogController(
        builtIn: builtIn,
        store: store ?? MemoryCatalogStore(),
        client: server.fake.client,
        session: session,
        deviceLocales: () => device,
      );
      addTearDown(catalogs.dispose);
      await catalogs.load();
      return catalogs;
    }

    test(
      'signed out, it shows the device language the server offers',
      () async {
        final session = await sessionOn(
          MemorySessionStore()..connection = signedOut(),
        );
        final catalogs = await following(session, device: const [Locale('de')]);

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
        final catalogs = await following(session, device: const [Locale('en')]);

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
      final catalogs = await following(session, device: const [Locale('de')]);

      await pumpEventQueue();

      expect(catalogs.catalog.language, 'de');
    });

    test('signing in picks again, with the setting', () async {
      server.setting = 'de';
      final session = await sessionOn(
        MemorySessionStore()..connection = signedOut(),
      );
      final catalogs = await following(session);
      await pumpEventQueue();
      expect(catalogs.catalog.language, 'en');

      await session.logIn('alice', 'correct horse battery');
      await pumpEventQueue();

      expect(catalogs.catalog.language, 'de');
    });

    test("signing out picks again, without the user's setting", () async {
      server.setting = 'de';
      final session = await sessionOn(signedInStore());
      final catalogs = await following(session);
      await pumpEventQueue();
      expect(catalogs.catalog.language, 'de');

      await session.logOut();
      await pumpEventQueue();

      expect(catalogs.catalog.language, 'en');
      expect(catalogs.catalog.text('login.title'), 'Sign in, from the server');
    });

    test('without a server nothing is asked; a new server is', () async {
      final session = await sessionOn(MemorySessionStore());
      final catalogs = await following(session, device: const [Locale('de')]);
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
      final catalogs = await following(session, device: const [Locale('de')]);
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
      await following(session);
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
          final catalogs = await following(
            session,
            device: const [Locale('de')],
          );
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
        final catalogs = await following(session, device: const [Locale('de')]);

        await pumpEventQueue();

        expect(catalogs.catalog, same(builtIn));
        expect(server.paths, ['/api/v1/locales']);
      },
    );

    test('a new catalog notifies the listeners once', () async {
      final session = await sessionOn(
        MemorySessionStore()..connection = signedOut(),
      );
      final catalogs = await following(session, device: const [Locale('de')]);
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
        final catalogs = await following(session);
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
        final catalogs = await following(session);

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
        final catalogs = await following(session, device: const [Locale('de')]);

        await pumpEventQueue();

        expect(catalogs.catalog.text('login.title'), 'Anmelden');
        expect(catalogs.catalog.text('login.subtitle'), 'Built in');
      },
    );

    group('the kept catalog', () {
      StoredCatalog keptGerman({
        Uri? from,
        String title = 'Angemeldet bleiben',
      }) => StoredCatalog(
        server: from ?? testOrigin,
        language: 'de',
        etag: '"de-1"',
        texts: {
          'login': {'title': title},
        },
      );

      Future<SessionController> signedOutSession() =>
          sessionOn(MemorySessionStore()..connection = signedOut());

      http.BaseRequest lastRequest() => server.fake.requests.last;

      test(
        'without one, the built-in English shows until the server answers',
        () async {
          final languages = Completer<http.Response>();
          server.answers['/api/v1/locales'] = () => languages.future;
          final catalogs = await following(
            await signedOutSession(),
            device: const [Locale('de')],
          );

          expect(catalogs.catalog, same(builtIn));

          languages.complete(server.languagesAnswer());
          await pumpEventQueue();
          expect(catalogs.catalog.text('login.title'), 'Anmelden');
        },
      );

      test('shows at once, before the server answers', () async {
        final languages = Completer<http.Response>();
        server.answers['/api/v1/locales'] = () => languages.future;
        final catalogs = await following(
          await signedOutSession(),
          device: const [Locale('de')],
          store: MemoryCatalogStore()..catalog = keptGerman(),
        );

        expect(catalogs.catalog.language, 'de');
        expect(catalogs.catalog.text('login.title'), 'Angemeldet bleiben');
        expect(
          catalogs.catalog.text('login.subtitle'),
          'Built in',
          reason: 'with the built-in English behind it',
        );

        languages.complete(server.languagesAnswer());
        await pumpEventQueue();
      });

      test('one from another server stays unseen', () async {
        final languages = Completer<http.Response>();
        server.answers['/api/v1/locales'] = () => languages.future;
        final catalogs = await following(
          await signedOutSession(),
          device: const [Locale('de')],
          store: MemoryCatalogStore()
            ..catalog = keptGerman(
              from: Uri.parse('https://other.example.ts.net'),
            ),
        );

        expect(catalogs.catalog, same(builtIn));

        languages.complete(server.languagesAnswer());
        await pumpEventQueue();
        expect(catalogs.catalog.text('login.title'), 'Anmelden');
        expect(lastRequest().headers.containsKey('if-none-match'), isFalse);
      });

      test(
        'is re-checked by its ETag; a 304 keeps it and writes nothing',
        () async {
          final store = MemoryCatalogStore()..catalog = keptGerman();
          final catalogs = await following(
            await signedOutSession(),
            device: const [Locale('de')],
            store: store,
          );
          var notified = 0;
          catalogs.addListener(() => notified++);

          await pumpEventQueue();

          expect(lastRequest().url.path, '/api/v1/locales/de/translations');
          expect(lastRequest().headers['if-none-match'], '"de-1"');
          expect(catalogs.catalog.text('login.title'), 'Angemeldet bleiben');
          expect(notified, 0);
          expect(store.writes, 0);
        },
      );

      test(
        'a changed catalog replaces it on screen and in the store',
        () async {
          server.etags['de'] = '"de-2"';
          final store = MemoryCatalogStore()..catalog = keptGerman();
          final catalogs = await following(
            await signedOutSession(),
            device: const [Locale('de')],
            store: store,
          );

          await pumpEventQueue();

          expect(lastRequest().headers['if-none-match'], '"de-1"');
          expect(catalogs.catalog.text('login.title'), 'Anmelden');
          expect(store.writes, 1);
          expect(store.catalog?.server, testOrigin);
          expect(store.catalog?.language, 'de');
          expect(store.catalog?.etag, '"de-2"');
          expect(store.catalog?.texts, {
            'login': {'title': 'Anmelden'},
          });
        },
      );

      test(
        'a fetched catalog is kept, and the next pick re-checks it',
        () async {
          server.setting = 'de';
          final store = MemoryCatalogStore();
          final session = await signedOutSession();
          await following(session, device: const [Locale('de')], store: store);
          await pumpEventQueue();
          expect(store.catalog?.etag, '"de-1"');

          await session.logIn('alice', 'correct horse battery');
          await pumpEventQueue();

          expect(lastRequest().headers['if-none-match'], '"de-1"');
          expect(store.writes, 1, reason: 'the 304 wrote nothing');
        },
      );

      test('another language is fetched without its ETag', () async {
        final store = MemoryCatalogStore()..catalog = keptGerman();
        final catalogs = await following(
          await signedOutSession(),
          store: store,
        );

        await pumpEventQueue();

        expect(lastRequest().url.path, '/api/v1/locales/en/translations');
        expect(lastRequest().headers.containsKey('if-none-match'), isFalse);
        expect(catalogs.catalog.language, 'en');
        expect(store.catalog?.language, 'en');
      });

      test('offline, it stays', () async {
        server.answers['/api/v1/locales'] = () async =>
            throw http.ClientException('Connection refused');
        final catalogs = await following(
          await signedOutSession(),
          device: const [Locale('de')],
          store: MemoryCatalogStore()..catalog = keptGerman(),
        );

        await pumpEventQueue();

        expect(catalogs.catalog.text('login.title'), 'Angemeldet bleiben');
      });

      test('broken kept texts are left out and replaced', () async {
        final store = MemoryCatalogStore()
          ..catalog = StoredCatalog(
            server: testOrigin,
            language: 'de',
            etag: '"de-1"',
            texts: {'login': 'no texts'},
          );
        final languages = Completer<http.Response>();
        server.answers['/api/v1/locales'] = () => languages.future;
        final catalogs = await following(
          await signedOutSession(),
          device: const [Locale('de')],
          store: store,
        );
        expect(catalogs.catalog, same(builtIn));

        languages.complete(server.languagesAnswer());
        await pumpEventQueue();

        expect(
          lastRequest().headers.containsKey('if-none-match'),
          isFalse,
          reason: 'its ETag names texts the app could not read',
        );
        expect(catalogs.catalog.text('login.title'), 'Anmelden');
        expect(store.catalog?.texts, {
          'login': {'title': 'Anmelden'},
        });
      });

      test('a write that fails keeps the new catalog on screen', () async {
        final catalogs = await following(
          await signedOutSession(),
          device: const [Locale('de')],
          store: _FullDisk(),
        );

        await pumpEventQueue();

        expect(catalogs.catalog.text('login.title'), 'Anmelden');
      });
    });

    test('a pick still on its way when disposed changes nothing', () async {
      final waiting = Completer<http.Response>();
      server.answers['/api/v1/locales/de/translations'] = () => waiting.future;
      final session = await sessionOn(
        MemorySessionStore()..connection = signedOut(),
      );
      final catalogs = CatalogController(
        builtIn: builtIn,
        store: MemoryCatalogStore(),
        client: server.fake.client,
        session: session,
        deviceLocales: () => const [Locale('de')],
      );
      await catalogs.load();
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
/// title and ETag; an `If-None-Match` naming the current ETag gets a 304. [setting] is the user's
/// language, and [answers] replaces the answer for a path.
class _CatalogServer {
  String? setting;
  final etags = {'en': '"en-1"', 'de': '"de-1"'};
  final answers = <String, Future<http.Response> Function()>{};

  static const _titles = {'en': 'Sign in, from the server', 'de': 'Anmelden'};

  http.Response languagesAnswer() => jsonAnswer([
    {'code': 'en', 'display_name': 'English', 'icon': null, 'is_default': true},
    {
      'code': 'de',
      'display_name': 'Deutsch',
      'icon': null,
      'is_default': false,
    },
  ]);

  late final fake = bookServer((request) async {
    if (answers[request.url.path] case final answer?) {
      return answer();
    }
    return switch (request.url.pathSegments) {
      ['api', 'v1', 'locales'] => languagesAnswer(),
      ['api', 'v1', 'locales', final code, 'translations']
          when _titles.containsKey(code) =>
        request.headers['if-none-match'] == etags[code]
            ? http.Response('', 304, headers: {'etag': etags[code]!})
            : http.Response(
                jsonEncode({
                  'login': {'title': _titles[code]},
                }),
                200,
                headers: {
                  'content-type': 'application/json',
                  'etag': etags[code]!,
                },
              ),
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

/// A store that keeps nothing: every write fails, as on a full disk.
class _FullDisk implements CatalogStore {
  @override
  Future<StoredCatalog?> read() async => null;

  @override
  Future<void> write(StoredCatalog catalog) async =>
      throw const FileSystemException('No space left on device');
}
