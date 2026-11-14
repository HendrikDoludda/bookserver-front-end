import 'package:bookserver/data/api_client.dart';
import 'package:bookserver/data/libraries_api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server.dart';

void main() {
  final origin = Uri.parse('https://books.example.ts.net');
  LibrariesApi apiFor(FakeServer server) =>
      LibrariesApi(ApiClient(server.client, origin));

  test('lists the libraries with the session token', () async {
    final server = FakeServer(
      (_) async => jsonAnswer([
        {
          'id': 1,
          'name': '/books',
          'library_type': 'Books',
          'cover_image': null,
          'description': null,
        },
        {
          'id': 2,
          'name': '/manga',
          'library_type': 'Manga',
          'cover_image': null,
          'description': null,
        },
      ]),
    );

    final libraries = await apiFor(server).list('session-1');

    expect(
      [for (final library in libraries) (library.id, library.name)],
      [(1, '/books'), (2, '/manga')],
    );
    final request = server.requests.single;
    expect(request.method, 'GET');
    expect(request.url.path, '/api/v1/libraries');
    expect(request.headers['authorization'], 'Bearer session-1');
  });

  test('an empty list is no libraries', () async {
    final server = FakeServer((_) async => jsonAnswer([]));
    expect(await apiFor(server).list('session-1'), isEmpty);
  });

  test('refuses an answer of another shape', () async {
    for (final body in <Object?>[
      {'id': 1, 'name': '/books'},
      [
        {'id': 1},
      ],
      [
        {'name': '/books'},
      ],
      [
        {'id': '1', 'name': '/books'},
      ],
    ]) {
      final server = FakeServer((_) async => jsonAnswer(body));
      await expectLater(
        apiFor(server).list('session-1'),
        throwsFormatException,
        reason: '$body',
      );
    }
  });
}
