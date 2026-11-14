import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookserver/data/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fake_server.dart';

void main() {
  final origin = Uri.parse('https://books.example.ts.net');

  ApiClient clientFor(
    FakeServer server, {
    Duration timeout = const Duration(seconds: 15),
  }) => ApiClient(server.client, origin, timeout: timeout);

  group('a request', () {
    test('goes to the origin with its JSON body and Bearer token', () async {
      final server = FakeServer((_) async => jsonAnswer({'ok': true}));

      await clientFor(server).postJson(
        '/api/v1/auth/login',
        body: {'name': 'Jörg'},
        bearer: 'token-1',
      );

      final request = server.requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://books.example.ts.net/api/v1/auth/login',
      );
      expect(request.headers['authorization'], 'Bearer token-1');
      expect(request.headers['content-type'], 'application/json');
      expect(request.headers['accept'], 'application/json');
      expect(utf8.decode(request.bodyBytes), '{"name":"Jörg"}');
      expect(request.followRedirects, isFalse);
    });

    test('without a token or a body sends neither', () async {
      final server = FakeServer((_) async => jsonAnswer([]));

      await clientFor(server).getJson('/api/v1/libraries');

      final request = server.requests.single;
      expect(request.method, 'GET');
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(request.headers.containsKey('content-type'), isFalse);
      expect(request.bodyBytes, isEmpty);
    });
  });

  group('a 2xx answer', () {
    test('is read as UTF-8 JSON, whatever its content type says', () async {
      for (final contentType in [
        'application/json',
        'text/plain',
        'application/octet-stream',
      ]) {
        final server = FakeServer(
          (_) async => http.Response.bytes(
            utf8.encode('{"text":"Prüfe"}'),
            200,
            headers: {'content-type': contentType},
          ),
        );
        expect(await clientFor(server).getJson('/x'), {
          'text': 'Prüfe',
        }, reason: contentType);
      }
    });

    test('without a body is null', () async {
      for (final status in [200, 204]) {
        final server = FakeServer((_) async => http.Response('', status));
        expect(
          await clientFor(server).postJson('/x'),
          isNull,
          reason: '$status',
        );
      }
    });

    test('that is not JSON is a FormatException', () async {
      final server = FakeServer((_) async => http.Response('<html>', 200));
      await expectLater(clientFor(server).getJson('/x'), throwsFormatException);
    });
  });

  group('a refusal', () {
    test(
      'with an error key is an ApiException with its status and key',
      () async {
        for (final (status, key) in [
          (400, 'invalid_request'),
          (401, 'unauthorized'),
          (429, 'too_many_attempts'),
          (503, 'email_not_configured'),
        ]) {
          final server = FakeServer(
            (_) async => jsonAnswer({'error': key}, status),
          );
          await expectLater(
            clientFor(server).getJson('/x'),
            throwsA(
              isA<ApiException>()
                  .having((e) => e.status, 'status', status)
                  .having((e) => e.key, 'key', key),
            ),
          );
        }
      },
    );

    test('without a key is a FormatException, a redirect included', () async {
      for (final answer in [
        http.Response('<html>Not found</html>', 404),
        http.Response(
          '',
          302,
          headers: {'location': 'https://wifi.example/login'},
        ),
        jsonAnswer({'message': 'no'}, 400),
      ]) {
        final server = FakeServer((_) async => answer);
        await expectLater(
          clientFor(server).getJson('/x'),
          throwsFormatException,
          reason: '${answer.statusCode}',
        );
      }
    });

    test(
      "a proxy's 502, 503 or 504 without a key is a ConnectionException",
      () async {
        for (final status in [502, 503, 504]) {
          final server = FakeServer(
            (_) async => http.Response('Bad Gateway', status),
          );
          await expectLater(
            clientFor(server).getJson('/x'),
            throwsA(isA<ConnectionException>()),
            reason: '$status',
          );
        }
      },
    );
  });

  group('no answer', () {
    test('a socket, TLS or client error is a ConnectionException', () async {
      for (final error in <Object>[
        const SocketException('Connection refused'),
        HandshakeException('certificate unknown'),
        http.ClientException('Connection closed'),
      ]) {
        final server = FakeServer((_) async => throw error);
        await expectLater(
          clientFor(server).getJson('/x'),
          throwsA(
            isA<ConnectionException>().having((e) => e.cause, 'cause', error),
          ),
        );
      }
    });

    test(
      'an answer slower than the timeout is a ConnectionException',
      () async {
        final server = FakeServer((_) => Completer<http.Response>().future);
        await expectLater(
          clientFor(
            server,
            timeout: const Duration(milliseconds: 10),
          ).getJson('/x'),
          throwsA(isA<ConnectionException>()),
        );
      },
    );
  });

  test('getText answers the body and refuses like the JSON calls', () async {
    final pong = FakeServer(
      (_) async =>
          http.Response('pong', 200, headers: {'content-type': 'text/plain'}),
    );
    expect(await clientFor(pong).getText('/health'), 'pong');
    expect(pong.requests.single.headers.containsKey('accept'), isFalse);

    final missing = FakeServer((_) async => http.Response('', 404));
    await expectLater(
      clientFor(missing).getText('/health'),
      throwsFormatException,
    );
  });
}
