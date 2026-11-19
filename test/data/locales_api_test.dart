import 'package:bookserver/data/api_client.dart';
import 'package:bookserver/data/locales_api.dart';
import 'package:flutter_test/flutter_test.dart';

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
        [for (final language in languages) (language.code, language.isDefault)],
        [('en', true), ('pt-BR', false)],
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
    test("reads a language's texts by namespace", () async {
      final texts = {
        'login': {'title': 'Entrar'},
      };
      final server = FakeServer((_) async => jsonAnswer(texts));

      expect(await apiFor(server).texts('pt-BR'), texts);
      expectPublicGet(server, '/api/v1/locales/pt-BR/translations');
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
