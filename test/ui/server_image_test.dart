import 'dart:convert';

import 'package:bookserver/data/api_client.dart';
import 'package:bookserver/ui/server_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fake_server.dart';
import '../support/images.dart';
import '../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Every test asks for the same paths on the same server: no image may come from a test before.
  setUp(() => PaintingBinding.instance.imageCache.clear());

  List<String> paths(FakeServer server) => [
    for (final request in server.requests) request.url.path,
  ];

  test('loads through the session, with its token', () async {
    final server = bookServer(
      (_) async => http.Response.bytes(
        onePixelPng,
        200,
        headers: {'content-type': 'image/png'},
      ),
    );
    final session = await signedInSession(server);

    final image = await loaded(ServerImage(session, '/api/v1/covers/book/1'));

    expect(image.image.width, 1);
    expect(paths(server), ['/api/v1/covers/book/1']);
    expect(server.requests.single.headers['authorization'], 'Bearer session-1');
  });

  test('renews a session token about to run out first', () async {
    final server = bookServer(
      (request) async => switch (request.url.path) {
        '/api/v1/auth/refresh' => jsonAnswer(
          tokensJson(session: 'session-2', refresh: 'refresh-2'),
        ),
        _ => http.Response.bytes(onePixelPng, 200),
      },
    );
    final session = await signedInSession(
      server,
      sessionLasts: const Duration(seconds: 30),
    );

    await loaded(ServerImage(session, '/api/v1/covers/book/1'));

    expect(paths(server), ['/api/v1/auth/refresh', '/api/v1/covers/book/1']);
    expect(server.requests.last.headers['authorization'], 'Bearer session-2');
  });

  test(
    'an image that failed loads anew the next time it is asked for',
    () async {
      var calls = 0;
      final server = bookServer(
        (_) async =>
            ++calls == 1 ? notFound() : http.Response.bytes(onePixelPng, 200),
      );
      final session = await signedInSession(server);
      final image = ServerImage(session, '/api/v1/covers/book/1');

      await expectLater(loaded(image), throwsA(isA<ApiException>()));
      // The cache lets go of a failed image a microtask after the failure.
      await Future<void>.delayed(Duration.zero);
      final info = await loaded(image);

      expect(info.image.width, 1);
      expect(paths(server), ['/api/v1/covers/book/1', '/api/v1/covers/book/1']);
    },
  );

  test(
    'an image whose bytes failed to decode loads anew the next time',
    () async {
      var calls = 0;
      final server = bookServer(
        (_) async => http.Response.bytes(
          ++calls == 1 ? utf8.encode('not an image') : onePixelPng,
          200,
        ),
      );
      final session = await signedInSession(server);
      final image = ServerImage(session, '/api/v1/covers/book/1');

      await expectLater(loaded(image), throwsA(anything));
      await Future<void>.delayed(Duration.zero);
      final info = await loaded(image);

      expect(info.image.width, 1);
      expect(calls, 2);
    },
  );

  test('an image that loaded comes from the cache the next time', () async {
    final server = bookServer(
      (_) async => http.Response.bytes(onePixelPng, 200),
    );
    final session = await signedInSession(server);
    final image = ServerImage(session, '/api/v1/covers/book/1');

    await loaded(image);
    await Future<void>.delayed(Duration.zero);
    await loaded(image);

    expect(paths(server), ['/api/v1/covers/book/1']);
  });

  test('a refusal is the error of the image', () async {
    final server = bookServer(
      (_) async => jsonAnswer({'error': 'not_found'}, 404),
    );
    final session = await signedInSession(server);

    await expectLater(
      loaded(ServerImage(session, '/api/v1/covers/book/1')),
      throwsA(isA<ApiException>().having((e) => e.key, 'key', 'not_found')),
    );
  });

  test('the cache keeps an image under its server and path', () async {
    final session = await signedInSession(bookServer());
    final key = await ServerImage(
      session,
      '/api/v1/covers/book/1',
    ).obtainKey(ImageConfiguration.empty);

    expect(key, ServerImageKey(testOrigin, '/api/v1/covers/book/1'));
    expect(
      key == ServerImageKey(Uri.parse('https://other.example'), key.path),
      isFalse,
      reason: 'the same path on another server is another image',
    );
    expect(key == ServerImageKey(testOrigin, '/api/v1/covers/book/2'), isFalse);
    expect(
      ServerImage(session, '/api/v1/covers/book/1'),
      ServerImage(session, '/api/v1/covers/book/1'),
      reason: 'a rebuild with an equal image keeps the loaded one',
    );
  });
}
