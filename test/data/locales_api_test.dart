import 'dart:convert';

import 'package:bookserver/data/api_client.dart';
import 'package:bookserver/data/locales_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fake_server.dart';

void main() {
  final origin = Uri.parse('https://books.example.ts.net');
  LocalesApi apiFor(FakeServer server) =>
      LocalesApi(ApiClient(server.client, origin));

  /// A GET for [path] without a token: the catalog's routes are public.
  void expectPublicGet(FakeServer server, String path) {
    final request = server.requests.single;
    expect(request.method, 'GET');
    expect(request.url.path, path);
    expect(request.headers.containsKey('authorization'), isFalse);
  }

  group('languages', () {
    test("lists the languages in the server's order", () async {
      final server = FakeServer(
        (_) async => jsonAnswer([
          {
            'code': 'en',
            'display_name': 'English',
            'icon': null,
            'is_default': true,
          },
          {
            'code': 'pt-BR',
            'display_name': 'Português',
            'icon': '📗',
            'is_default': false,
          },
        ]),
      );

      final languages = await apiFor(server).languages();

      expect(
        [
          for (final language in languages)
            (
              language.code,
              language.displayName,
              language.icon,
              language.isDefault,
            ),
        ],
        [('en', 'English', null, true), ('pt-BR', 'Português', '📗', false)],
      );
      expectPublicGet(server, '/api/v1/locales');
    });

    test('refuses anything but a list of languages', () async {
      final answers = <Object?>[
        {'code': 'en', 'is_default': true},
        [
          {'code': 'en'},
        ],
        [
          {'code': 3, 'is_default': true},
        ],
        [
          {'code': 'en', 'is_default': 'yes'},
        ],
      ];
      for (final answer in answers) {
        final server = FakeServer((_) async => jsonAnswer(answer));
        await expectLater(
          apiFor(server).languages(),
          throwsFormatException,
          reason: '$answer',
        );
      }
    });
  });

  group('texts', () {
    final texts = {
      'login': {'title': 'Entrar'},
    };
    http.Response tagged(Object? body, {String? etag}) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json', 'etag': ?etag},
    );

    test("reads a language's texts by namespace, with their ETag", () async {
      final server = FakeServer((_) async => tagged(texts, etag: '"v1"'));

      final answer = await apiFor(server).texts('pt-BR');

      expect(
        answer,
        isA<CatalogTexts>()
            .having((a) => a.texts, 'texts', texts)
            .having((a) => a.etag, 'etag', '"v1"'),
      );
      expectPublicGet(server, '/api/v1/locales/pt-BR/translations');
      expect(
        server.requests.single.headers.containsKey('if-none-match'),
        isFalse,
        reason: 'no ETag to send',
      );
    });

    test('a catalog the server sends without an ETag has none', () async {
      final server = FakeServer((_) async => tagged(texts));

      final answer = await apiFor(server).texts('de');

      expect(answer, isA<CatalogTexts>().having((a) => a.etag, 'etag', null));
    });

    test('sends the ETag it has; a 304 says the texts are unchanged', () async {
      final server = FakeServer(
        (request) async => request.headers['if-none-match'] == '"v1"'
            ? http.Response('', 304, headers: {'etag': '"v1"'})
            : tagged(texts, etag: '"v2"'),
      );

      expect(
        await apiFor(server).texts('de', etag: '"v1"'),
        isA<CatalogUnchanged>(),
      );
      expect(
        await apiFor(server).texts('de', etag: '"v0"'),
        isA<CatalogTexts>().having((a) => a.etag, 'etag', '"v2"'),
        reason: 'an ETag that no longer matches gets the texts',
      );
    });

    test('refuses texts that are no object of namespaces', () async {
      for (final body in <Object?>[
        ['login'],
        'Entrar',
        null,
      ]) {
        final server = FakeServer((_) async => tagged(body, etag: '"v1"'));
        await expectLater(
          apiFor(server).texts('de'),
          throwsFormatException,
          reason: '$body',
        );
      }
      final notJson = FakeServer((_) async => http.Response('<html>', 200));
      await expectLater(apiFor(notJson).texts('de'), throwsFormatException);
    });

    test("a language the server doesn't offer is its refusal", () async {
      final server = FakeServer(
        (_) async => jsonAnswer({'error': 'not_found'}, 404),
      );

      await expectLater(
        apiFor(server).texts('fr'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.status, 'status', 404)
              .having((e) => e.key, 'key', 'not_found'),
        ),
      );
    });
  });
}
