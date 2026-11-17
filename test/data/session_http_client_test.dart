import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/data/session_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fake_server.dart';
import '../support/screens.dart';

void main() {
  /// A range request as pdfrx sends one.
  http.Request rangeRequest([
    String url = '$testAddress/api/v1/books/7/file',
  ]) =>
      http.Request('GET', Uri.parse(url))..headers['Range'] = 'bytes=0-1048575';

  http.Response partial() =>
      http.Response('%PDF', 206, headers: {'content-range': 'bytes 0-3/1000'});

  List<String> paths(FakeServer server) => [
    for (final request in server.requests) request.url.path,
  ];

  test('sends a request with the session token, its Range passed on', () async {
    final server = bookServer((_) async => partial());
    final session = await signedInSession(server);

    final response = await SessionHttpClient(session).send(rangeRequest());

    expect(response.statusCode, 206);
    expect(response.headers['content-range'], 'bytes 0-3/1000');
    expect(await response.stream.bytesToString(), '%PDF');
    final request = server.requests.single;
    expect(request.url.path, '/api/v1/books/7/file');
    expect(request.headers['authorization'], 'Bearer session-1');
    expect(request.headers['range'], 'bytes=0-1048575');
  });

  test(
    'a refused token is renewed, and the request sent again with the new one',
    () async {
      var tries = 0;
      final server = bookServer(
        (request) async => switch (request.url.path) {
          '/api/v1/auth/refresh' => jsonAnswer(
            tokensJson(session: 'session-2', refresh: 'refresh-2'),
          ),
          _ =>
            ++tries == 1
                ? jsonAnswer({'error': 'unauthorized'}, 401)
                : partial(),
        },
      );
      final session = await signedInSession(server);

      final response = await SessionHttpClient(session).send(rangeRequest());

      expect(response.statusCode, 206);
      expect(paths(server), [
        '/api/v1/books/7/file',
        '/api/v1/auth/refresh',
        '/api/v1/books/7/file',
      ]);
      expect(server.requests.last.headers['authorization'], 'Bearer session-2');
      expect(server.requests.last.headers['range'], 'bytes=0-1048575');
    },
  );

  test('renews a session token about to run out before the request', () async {
    final server = bookServer(
      (request) async => switch (request.url.path) {
        '/api/v1/auth/refresh' => jsonAnswer(
          tokensJson(session: 'session-2', refresh: 'refresh-2'),
        ),
        _ => partial(),
      },
    );
    final session = await signedInSession(
      server,
      sessionLasts: const Duration(seconds: 30),
    );

    await SessionHttpClient(session).send(rangeRequest());

    expect(paths(server), ['/api/v1/auth/refresh', '/api/v1/books/7/file']);
    expect(server.requests.last.headers['authorization'], 'Bearer session-2');
  });

  test('sends nothing to another server, nor anything but a GET', () async {
    final server = bookServer((_) async => partial());
    final client = SessionHttpClient(await signedInSession(server));

    await expectLater(
      client.send(
        rangeRequest('https://elsewhere.example/api/v1/books/7/file'),
      ),
      throwsArgumentError,
    );
    await expectLater(
      client.send(
        http.Request('POST', Uri.parse('$testAddress/api/v1/books/7/file')),
      ),
      throwsArgumentError,
    );
    expect(server.requests, isEmpty);
  });

  test("closing it leaves the session's own client open", () async {
    final server = bookServer((_) async => partial());
    final watched = _CloseWatcher(server.client);
    final session = SessionController(
      store: signedInStore(),
      client: watched,
      platform: 'macos',
    );
    await session.load();

    SessionHttpClient(session).close();

    expect(watched.closed, isFalse);
    final response = await SessionHttpClient(session).send(rangeRequest());
    expect(response.statusCode, 206);
  });
}

/// Passes every request on to [_inner] and notes whether it was closed.
class _CloseWatcher extends http.BaseClient {
  _CloseWatcher(this._inner);

  final http.Client _inner;
  var closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() => closed = true;
}
