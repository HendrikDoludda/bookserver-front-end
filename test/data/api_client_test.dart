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

  test(
    'getBytes answers the body as it came and refuses like the JSON calls',
    () async {
      final png = [0x89, 0x50, 0x4e, 0x47, 0xff, 0x00];
      final server = FakeServer(
        (_) async => http.Response.bytes(
          png,
          200,
          headers: {'content-type': 'image/png'},
        ),
      );
      expect(
        await clientFor(server)
            .getBytes('/api/v1/covers/book/1', bearer: 'token-1'),
        png,
      );
      final request = server.requests.single;
      expect(request.headers['authorization'], 'Bearer token-1');
      expect(request.headers.containsKey('accept'), isFalse);
      expect(request.followRedirects, isFalse);

      final missing = FakeServer(
        (_) async => jsonAnswer({'error': 'not_found'}, 404),
      );
      await expectLater(
        clientFor(missing).getBytes('/api/v1/covers/book/2'),
        throwsA(isA<ApiException>().having((e) => e.key, 'key', 'not_found')),
      );
    },
  );

  group('a download', () {
    late Directory folder;
    setUp(
      () => folder = Directory.systemTemp.createTempSync('bookserver-test-'),
    );
    tearDown(() => folder.deleteSync(recursive: true));

    File target() => File('${folder.path}/book.pdf');

    ApiClient downloaderFor(
      StreamingFakeServer server, {
      Duration timeout = const Duration(seconds: 15),
    }) => ApiClient(server.client, origin, timeout: timeout);

    /// [parts] as the chunks of an answer's body, each [gap] after the one before.
    Stream<List<int>> chunks(
      List<String> parts, {
      Duration gap = Duration.zero,
    }) async* {
      for (final part in parts) {
        await Future<void>.delayed(gap);
        yield utf8.encode(part);
      }
    }

    test('writes the body to the file and reports every step', () async {
      final server = StreamingFakeServer(
        (_) async => http.StreamedResponse(
          chunks(['%PDF', '-1.7', ' tiny']),
          200,
          contentLength: 13,
        ),
      );
      final progress = <(int, int?)>[];

      await downloaderFor(server).download(
        '/api/v1/books/1/file',
        target(),
        bearer: 'token-1',
        onProgress: (received, total) => progress.add((received, total)),
      );

      expect(target().readAsStringSync(), '%PDF-1.7 tiny');
      expect(progress, [(4, 13), (8, 13), (13, 13)]);
      final request = server.requests.single;
      expect(
        request.url.toString(),
        'https://books.example.ts.net/api/v1/books/1/file',
      );
      expect(request.headers['authorization'], 'Bearer token-1');
      expect(request.followRedirects, isFalse);
    });

    test('without an announced length reports no total', () async {
      final server = StreamingFakeServer(
        (_) async => http.StreamedResponse(chunks(['ab', 'c']), 200),
      );
      final progress = <(int, int?)>[];

      await downloaderFor(server).download(
        '/x',
        target(),
        onProgress: (received, total) => progress.add((received, total)),
      );

      expect(progress, [(2, null), (3, null)]);
    });

    test(
      'times out on a gap between chunks, never on the whole download',
      () async {
        // Each gap is far below the timeout, all of them together far above it.
        final steady = StreamingFakeServer(
          (_) async => http.StreamedResponse(
            chunks([
              'a',
              'b',
              'c',
              'd',
              'e',
              'f',
            ], gap: const Duration(milliseconds: 40)),
            200,
          ),
        );
        await downloaderFor(
          steady,
          timeout: const Duration(milliseconds: 150),
        ).download('/x', target());
        expect(target().readAsStringSync(), 'abcdef');

        final stalled = StreamController<List<int>>()..add(utf8.encode('half'));
        addTearDown(stalled.close);
        final stalling = StreamingFakeServer(
          (_) async => http.StreamedResponse(stalled.stream, 200),
        );
        await expectLater(
          downloaderFor(
            stalling,
            timeout: const Duration(milliseconds: 50),
          ).download('/x', target()),
          throwsA(isA<ConnectionException>()),
        );
        expect(target().existsSync(), isFalse, reason: 'the half is gone');
      },
    );

    test('a connection lost midway leaves no file', () async {
      Stream<List<int>> broken() async* {
        yield utf8.encode('half');
        throw http.ClientException('Connection reset by peer');
      }

      final server = StreamingFakeServer(
        (_) async => http.StreamedResponse(broken(), 200),
      );
      await expectLater(
        downloaderFor(server).download('/x', target()),
        throwsA(isA<ConnectionException>()),
      );
      expect(target().existsSync(), isFalse);
    });

    test('a refusal is an ApiException and makes no file', () async {
      final server = StreamingFakeServer(
        (_) async => http.StreamedResponse(
          Stream.value(utf8.encode('{"error":"unauthorized"}')),
          401,
        ),
      );
      await expectLater(
        downloaderFor(server).download('/x', target()),
        throwsA(
          isA<ApiException>()
              .having((e) => e.status, 'status', 401)
              .having((e) => e.key, 'key', 'unauthorized'),
        ),
      );
      expect(target().existsSync(), isFalse);
    });

    test('a file that cannot be written is a FileSystemException, not a lost connection', () async {
      final server = StreamingFakeServer(
        (_) async => http.StreamedResponse(chunks(['%PDF']), 200),
      );
      final nowhere = File('${folder.path}/no-such-folder/book.pdf');

      await expectLater(
        downloaderFor(server).download('/x', nowhere),
        throwsA(isA<FileSystemException>()),
      );
      expect(nowhere.existsSync(), isFalse);
    });
  });

  group('a stream', () {
    ApiClient streamerFor(
      StreamingFakeServer server, {
      Duration timeout = ApiClient.defaultTimeout,
    }) => ApiClient(server.client, origin, timeout: timeout);

    Stream<List<int>> body(String text) => Stream.value(utf8.encode(text));

    test(
      'answers a 206 with its head and body, sending the token and the Range',
      () async {
        final server = StreamingFakeServer(
          (_) async => http.StreamedResponse(
            body('%PDF'),
            206,
            contentLength: 4,
            headers: {'content-range': 'bytes 0-3/1000'},
          ),
        );

        final response = await streamerFor(server).stream(
          '/api/v1/books/7/file',
          bearer: 'token-1',
          headers: {'Range': 'bytes=0-3'},
        );

        expect(response.statusCode, 206);
        expect(response.contentLength, 4);
        expect(response.headers['content-range'], 'bytes 0-3/1000');
        expect(await response.stream.bytesToString(), '%PDF');
        final request = server.requests.single;
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          'https://books.example.ts.net/api/v1/books/7/file',
        );
        expect(request.headers['authorization'], 'Bearer token-1');
        expect(request.headers['range'], 'bytes=0-3');
        expect(request.followRedirects, isFalse);
      },
    );

    test('keeps its own token over one in the headers', () async {
      final server = StreamingFakeServer(
        (_) async => http.StreamedResponse(body(''), 200),
      );

      await streamerFor(server).stream(
        '/x',
        bearer: 'token-1',
        headers: {'Authorization': 'Bearer other'},
      );

      expect(server.requests.single.headers['authorization'], 'Bearer token-1');
    });

    test('answers a 304 as it is', () async {
      final server = StreamingFakeServer(
        (_) async => http.StreamedResponse(body(''), 304),
      );

      final response = await streamerFor(server)
          .stream('/x', headers: {'If-None-Match': '"v1"'});

      expect(response.statusCode, 304);
      expect(server.requests.single.headers['if-none-match'], '"v1"');
    });

    test('a refusal throws what the other calls throw', () async {
      final refusals = <(int, String, Matcher)>[
        (
          401,
          '{"error":"unauthorized"}',
          isA<ApiException>()
              .having((e) => e.status, 'status', 401)
              .having((e) => e.key, 'key', 'unauthorized'),
        ),
        (
          404,
          '{"error":"not_found"}',
          isA<ApiException>().having((e) => e.key, 'key', 'not_found'),
        ),
        (502, '', isA<ConnectionException>()),
        (500, '', isA<FormatException>()),
      ];
      for (final (status, text, matcher) in refusals) {
        final server = StreamingFakeServer(
          (_) async => http.StreamedResponse(body(text), status),
        );
        await expectLater(
          streamerFor(server).stream('/x'),
          throwsA(matcher),
          reason: '$status $text',
        );
      }
    });

    test('no answer is a ConnectionException', () async {
      final server = StreamingFakeServer(
        (_) async => throw http.ClientException('Connection refused'),
      );

      await expectLater(
        streamerFor(server).stream('/x'),
        throwsA(isA<ConnectionException>()),
      );
    });

    test('a body that stalls ends in a ConnectionException', () async {
      final stalled = StreamController<List<int>>()..add(utf8.encode('half'));
      addTearDown(stalled.close);
      final server = StreamingFakeServer(
        (_) async => http.StreamedResponse(stalled.stream, 206),
      );

      final response = await streamerFor(
        server,
        timeout: const Duration(milliseconds: 50),
      ).stream('/x');

      await expectLater(
        response.stream.toList(),
        throwsA(isA<ConnectionException>()),
      );
    });
  });

  group('revalidate', () {
    test('names the ETag it has in If-None-Match, and asks for JSON', () async {
      final server = FakeServer((_) async => jsonAnswer({'ok': true}));

      await clientFor(server)
          .revalidate('/api/v1/locales/de/translations', etag: '"v1"');
      await clientFor(server).revalidate('/api/v1/locales/de/translations');

      final [withTag, without] = server.requests;
      expect(withTag.method, 'GET');
      expect(withTag.url, origin.resolve('/api/v1/locales/de/translations'));
      expect(withTag.headers['if-none-match'], '"v1"');
      expect(withTag.headers['accept'], 'application/json');
      expect(without.headers.containsKey('if-none-match'), isFalse);
    });

    test('a 304 is an answer, and so is a 2xx with its whole body', () async {
      final server = FakeServer(
        (request) async => request.headers['if-none-match'] == '"v1"'
            ? http.Response('', 304)
            : http.Response('{"a": 1}', 200, headers: {'etag': '"v2"'}),
      );

      final unchanged = await clientFor(server).revalidate('/x', etag: '"v1"');
      expect(unchanged.statusCode, 304);

      final changed = await clientFor(server).revalidate('/x', etag: '"v0"');
      expect(changed.statusCode, 200);
      expect(changed.body, '{"a": 1}');
      expect(changed.headers['etag'], '"v2"');
    });

    test('refuses like the JSON calls', () async {
      final refused = FakeServer(
        (_) async => jsonAnswer({'error': 'not_found'}, 404),
      );
      await expectLater(
        clientFor(refused).revalidate('/x'),
        throwsA(isA<ApiException>().having((e) => e.key, 'key', 'not_found')),
      );

      final down = FakeServer(
        (_) async => throw http.ClientException('Connection refused'),
      );
      await expectLater(
        clientFor(down).revalidate('/x'),
        throwsA(isA<ConnectionException>()),
      );
    });
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
