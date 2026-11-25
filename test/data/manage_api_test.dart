import 'dart:convert';

import 'package:bookserver/data/api_client.dart';
import 'package:bookserver/data/manage_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fake_server.dart';

void main() {
  final origin = Uri.parse('https://books.example.ts.net');
  ManageApi apiFor(FakeServer server) =>
      ManageApi(ApiClient(server.client, origin));

  /// A library exactly as the server sends one.
  Map<String, Object?> library({
    int id = 3,
    String type = 'comics',
    String? description = 'Picked by hand',
  }) => {
    'id': id,
    'name': 'Favourites',
    'library_type': type,
    'description': description,
    'series_count': 2,
  };

  /// A series exactly as `GET /api/v1/series` sends one.
  Map<String, Object?> series({List<Object?> libraryIds = const [3]}) => {
    'id': 4,
    'name': 'Berserk',
    'description': null,
    'start_release_year': 1989,
    'end_release_year': null,
    'book_count': 41,
    'library_ids': libraryIds,
  };

  http.Request onlyRequest(FakeServer server) => server.requests.single;

  test('libraries reads every field, with the session', () async {
    final server = FakeServer((_) async => jsonAnswer([library()]));

    final libraries = await apiFor(server).libraries('session-1');

    final favourites = libraries.single;
    expect(favourites.id, 3);
    expect(favourites.name, 'Favourites');
    expect(favourites.type, LibraryType.comics);
    expect(favourites.description, 'Picked by hand');
    expect(favourites.seriesCount, 2);
    expect(onlyRequest(server).url.path, '/api/v1/libraries');
    expect(onlyRequest(server).headers['authorization'], 'Bearer session-1');
  });

  test('a type this app does not know reads as others', () async {
    final server = FakeServer(
      (_) async => jsonAnswer([library(type: 'atlases')]),
    );

    final libraries = await apiFor(server).libraries('session-1');

    expect(libraries.single.type, LibraryType.others);
  });

  test('createLibrary posts every field and answers the new library', () async {
    final server = FakeServer((_) async => jsonAnswer(library(), 201));

    final created = await apiFor(server).createLibrary(
      'session-1',
      name: 'Favourites',
      type: LibraryType.comics,
      description: null,
    );

    expect(created.id, 3);
    final request = onlyRequest(server);
    expect(request.method, 'POST');
    expect(request.url.path, '/api/v1/libraries');
    expect(jsonDecode(request.body), {
      'name': 'Favourites',
      'library_type': 'comics',
      'description': null,
    });
  });

  test('changeLibrary sends only the fields given, and null to clear the description', () async {
    for (final (changes, body) in <(Future<void> Function(ManageApi), Object)>[
      (
        (api) => api.changeLibrary('session-1', 3, name: 'Manga'),
        {'name': 'Manga'},
      ),
      (
        (api) => api.changeLibrary('session-1', 3, type: LibraryType.books),
        {'library_type': 'books'},
      ),
      (
        (api) =>
            api.changeLibrary('session-1', 3, description: const Change(null)),
        {'description': null},
      ),
      (
        (api) => api.changeLibrary(
          'session-1',
          3,
          description: const Change('Japanese comics'),
        ),
        {'description': 'Japanese comics'},
      ),
    ]) {
      final server = FakeServer((_) async => jsonAnswer(library()));

      await changes(apiFor(server));

      final request = onlyRequest(server);
      expect(request.method, 'PATCH');
      expect(request.url.path, '/api/v1/libraries/3');
      expect(jsonDecode(request.body), body);
    }
  });

  test('allSeries reads every field and the libraries each is in', () async {
    final server = FakeServer(
      (_) async => jsonAnswer([series(), series(libraryIds: const [])]),
    );

    final listed = await apiFor(server).allSeries('session-1');

    final berserk = listed.first;
    expect(berserk.id, 4);
    expect(berserk.name, 'Berserk');
    expect(berserk.description, isNull);
    expect(berserk.startYear, 1989);
    expect(berserk.endYear, isNull);
    expect(berserk.bookCount, 41);
    expect(berserk.libraryIds, [3]);
    expect(listed.last.libraryIds, isEmpty);
    expect(onlyRequest(server).url.path, '/api/v1/series');
  });

  test('a series or library in the wrong shape is a FormatException', () async {
    for (final (call, answer) in <(Future<void> Function(ManageApi), Object?)>[
      (
        (api) => api.allSeries('session-1'),
        [
          series(libraryIds: ['3']),
        ],
      ),
      (
        (api) => api.allSeries('session-1'),
        [
          <String, Object?>{'id': 4},
        ],
      ),
      (
        (api) => api.libraries('session-1'),
        [
          <String, Object?>{'id': 3},
        ],
      ),
      ((api) => api.libraries('session-1'), {'id': 3}),
    ]) {
      final server = FakeServer((_) async => jsonAnswer(answer));
      await expectLater(call(apiFor(server)), throwsFormatException);
    }
  });

  test('a series goes into a library with PUT and out with DELETE', () async {
    final server = FakeServer((_) async => http.Response('', 204));
    final api = apiFor(server);

    await api.addSeries('session-1', 3, 4);
    await api.removeSeries('session-1', 3, 4);

    expect(
      [
        for (final request in server.requests)
          '${request.method} ${request.url.path}',
      ],
      [
        'PUT /api/v1/libraries/3/series/4',
        'DELETE /api/v1/libraries/3/series/4',
      ],
    );
  });

  test(
    'changeSeries sends only the fields given; Change(null) clears one',
    () async {
      final server = FakeServer((_) async => jsonAnswer(series()));

      await apiFor(server).changeSeries(
        'session-1',
        4,
        name: 'Berserk',
        startYear: const Change(null),
        endYear: const Change(2021),
      );

      final request = onlyRequest(server);
      expect(request.method, 'PATCH');
      expect(request.url.path, '/api/v1/series/4');
      expect(jsonDecode(request.body), {
        'name': 'Berserk',
        'start_release_year': null,
        'end_release_year': 2021,
      });
    },
  );

  test('deleting passes the server\'s refusal on', () async {
    final server = FakeServer(
      (_) async => jsonAnswer({'error': 'series_not_empty'}, 409),
    );

    await expectLater(
      apiFor(server).deleteSeries('session-1', 4),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 409)
            .having((e) => e.key, 'key', 'series_not_empty'),
      ),
    );
    expect(onlyRequest(server).method, 'DELETE');
    expect(onlyRequest(server).url.path, '/api/v1/series/4');
  });

  test(
    'mergeSeries posts the merged series to the kept one\'s merges',
    () async {
      final server = FakeServer(
        (_) async => jsonAnswer(series()..remove('library_ids')),
      );

      await apiFor(server).mergeSeries('session-1', 4, 7);

      final request = onlyRequest(server);
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/series/4/merges');
      expect(jsonDecode(request.body), {'series_id': 7});
      expect(request.headers['authorization'], 'Bearer session-1');
    },
  );

  test('merging passes the server\'s refusal on', () async {
    final server = FakeServer(
      (_) async => jsonAnswer({'error': 'invalid_request'}, 400),
    );

    await expectLater(
      apiFor(server).mergeSeries('session-1', 4, 4),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 400)
            .having((e) => e.key, 'key', 'invalid_request'),
      ),
    );
  });

  test('deleteLibrary sends a DELETE for the library', () async {
    final server = FakeServer((_) async => http.Response('', 204));

    await apiFor(server).deleteLibrary('session-1', 3);

    expect(onlyRequest(server).method, 'DELETE');
    expect(onlyRequest(server).url.path, '/api/v1/libraries/3');
  });

  test(
    'a cover is chosen with PUT and its id, and reset with DELETE',
    () async {
      final server = FakeServer((_) async => http.Response('', 204));
      final api = apiFor(server);

      await api.chooseSeriesCover('session-1', 4, 12);
      await api.resetSeriesCover('session-1', 4);
      await api.chooseLibraryCover('session-1', 3, 4);
      await api.resetLibraryCover('session-1', 3);

      expect(
        [
          for (final request in server.requests)
            '${request.method} ${request.url.path} ${request.body}'.trim(),
        ],
        [
          'PUT /api/v1/series/4/cover {"book_id":12}',
          'DELETE /api/v1/series/4/cover',
          'PUT /api/v1/libraries/3/cover {"series_id":4}',
          'DELETE /api/v1/libraries/3/cover',
        ],
      );
      expect(
        server.requests.map((request) => request.headers['authorization']),
        everyElement('Bearer session-1'),
      );
    },
  );

  test('a refused cover passes the server\'s answer on', () async {
    final server = FakeServer(
      (_) async => jsonAnswer({'error': 'invalid_request'}, 400),
    );

    await expectLater(
      apiFor(server).chooseSeriesCover('session-1', 4, 99),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 400)
            .having((e) => e.key, 'key', 'invalid_request'),
      ),
    );
  });

  /// A folder exactly as `GET /api/v1/directories` sends one.
  Map<String, Object?> directory({Object? libraryId = 3}) => {
    'id': 7,
    'path': '/books/Manga',
    'library_id': libraryId,
  };

  test('directories reads each folder and its library, or none', () async {
    final server = FakeServer(
      (_) async => jsonAnswer([directory(), directory(libraryId: null)]),
    );

    final directories = await apiFor(server).directories('session-1');

    expect(
      [for (final one in directories) (one.id, one.path, one.libraryId)],
      [(7, '/books/Manga', 3), (7, '/books/Manga', null)],
    );
    expect(onlyRequest(server).url.path, '/api/v1/directories');
    expect(onlyRequest(server).headers['authorization'], 'Bearer session-1');
  });

  test(
    'addDirectory sends a type and a name only with a library of its own',
    () async {
      final server = FakeServer((_) async => jsonAnswer(directory(), 201));
      final api = apiFor(server);

      final added = await api.addDirectory(
        'session-1',
        path: '/books/Manga',
        libraryType: LibraryType.comics,
        libraryName: 'Manga',
      );
      await api.addDirectory(
        'session-1',
        path: '/books/Manga',
        libraryType: LibraryType.books,
      );
      await api.addDirectory('session-1', path: '/books/inbox');

      expect((added.id, added.libraryId), (7, 3));
      expect(
        [for (final request in server.requests) request.method],
        ['POST', 'POST', 'POST'],
      );
      expect(
        [for (final request in server.requests) jsonDecode(request.body)],
        [
          {
            'path': '/books/Manga',
            'create_library': true,
            'library_type': 'comics',
            'library_name': 'Manga',
          },
          {
            'path': '/books/Manga',
            'create_library': true,
            'library_type': 'books',
          },
          {'path': '/books/inbox', 'create_library': false},
        ],
      );
    },
  );

  test('removeDirectory sends a DELETE for the folder', () async {
    final server = FakeServer((_) async => http.Response('', 204));

    await apiFor(server).removeDirectory('session-1', 7);

    expect(onlyRequest(server).method, 'DELETE');
    expect(onlyRequest(server).url.path, '/api/v1/directories/7');
  });

  test('a folder in the wrong shape is a FormatException', () async {
    for (final answer in <Object?>[
      [
        <String, Object?>{'id': 7, 'path': '/books/Manga'},
      ],
      [directory(libraryId: 'Manga')],
      [
        {...directory(), 'id': '7'},
      ],
      directory(),
    ]) {
      final server = FakeServer((_) async => jsonAnswer(answer));
      await expectLater(
        apiFor(server).directories('session-1'),
        throwsFormatException,
        reason: '$answer',
      );
    }
  });
}
