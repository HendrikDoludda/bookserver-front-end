import 'dart:convert';

import 'package:http/http.dart' as http;

import 'fake_server.dart';
import 'screens.dart';

/// Stands in for a server an admin manages: it answers the account as an admin's, and the
/// library and series calls from its own lists, which those calls change as the server would.
class ManageServer {
  ManageServer({
    List<Map<String, Object?>> libraries = const [],
    List<Map<String, Object?>> series = const [],
  }) : libraries = [
         for (final one in libraries) {...one},
       ],
       series = [
         for (final one in series)
           {
             ...one,
             'library_ids': [...one['library_ids']! as List<Object?>],
           },
       ];

  /// The libraries as `GET /api/v1/libraries` sends them, but without their `series_count`,
  /// which is counted from [series].
  final List<Map<String, Object?>> libraries;

  /// The series as `GET /api/v1/series` sends them.
  final List<Map<String, Object?>> series;

  /// Answers a request before the lists do, when it gives an answer: a refusal, say.
  http.Response? Function(http.Request request)? refuse;

  var _nextLibraryId = 100;

  late final FakeServer fake = bookServer(_answer);

  /// The requests that changed something, as `METHOD /path` with their JSON body if any.
  List<String> get changes => [
    for (final request in fake.requests)
      if (request.method != 'GET')
        '${request.method} ${request.url.path}'
            '${request.body.isEmpty ? '' : ' ${request.body}'}',
  ];

  Future<http.Response> _answer(http.Request request) async {
    if (refuse?.call(request) case final refusal?) {
      return refusal;
    }
    final segments = request.url.pathSegments.skip(2).toList();
    final body = request.body.isEmpty
        ? const <String, Object?>{}
        : jsonDecode(request.body) as Map<String, Object?>;
    return switch ((request.method, segments)) {
      ('GET', ['account']) => jsonAnswer({
        'id': 1,
        'username': 'alice',
        'email': 'alice@example.com',
        'email_verified': true,
        'role': 'admin',
        'created_at': 1700000000,
        'last_login': null,
      }),
      ('GET', ['libraries']) => jsonAnswer([
        for (final library in libraries) _counted(library),
      ]),
      ('POST', ['libraries']) => _create(body),
      ('PATCH', ['libraries', final id]) => _change(
        _library(id),
        body,
        counted: true,
      ),
      ('DELETE', ['libraries', final id]) => _deleteLibrary(id),
      ('PUT', ['libraries', final id, 'series', final seriesId]) => _link(
        id,
        seriesId,
        add: true,
      ),
      ('DELETE', ['libraries', final id, 'series', final seriesId]) => _link(
        id,
        seriesId,
        add: false,
      ),
      ('GET', ['series']) => jsonAnswer(series),
      ('PATCH', ['series', final id]) => _change(_series(id), body),
      ('DELETE', ['series', final id]) => _deleteSeries(id),
      _ => notFound(),
    };
  }

  Map<String, Object?> _counted(Map<String, Object?> library) => {
    ...library,
    'series_count': series
        .where(
          (one) =>
              (one['library_ids']! as List<Object?>).contains(library['id']),
        )
        .length,
  };

  Map<String, Object?>? _library(String id) =>
      libraries.where((one) => '${one['id']}' == id).firstOrNull;

  Map<String, Object?>? _series(String id) =>
      series.where((one) => '${one['id']}' == id).firstOrNull;

  http.Response _create(Map<String, Object?> body) {
    final library = {
      'id': _nextLibraryId++,
      'name': body['name'],
      'library_type': body['library_type'],
      'description': body['description'],
    };
    libraries.add(library);
    return jsonAnswer(_counted(library), 201);
  }

  http.Response _change(
    Map<String, Object?>? row,
    Map<String, Object?> body, {
    bool counted = false,
  }) {
    if (row == null) {
      return notFound();
    }
    row.addAll(body);
    return jsonAnswer(counted ? _counted(row) : row);
  }

  http.Response _deleteLibrary(String id) {
    final library = _library(id);
    if (library == null) {
      return notFound();
    }
    libraries.remove(library);
    for (final one in series) {
      (one['library_ids']! as List<Object?>).remove(library['id']);
    }
    return http.Response('', 204);
  }

  http.Response _link(String id, String seriesId, {required bool add}) {
    final library = _library(id);
    final one = _series(seriesId);
    if (library == null || one == null) {
      return notFound();
    }
    final libraryIds = one['library_ids']! as List<Object?>;
    libraryIds.remove(library['id']);
    if (add) {
      libraryIds.add(library['id']);
    }
    return http.Response('', 204);
  }

  http.Response _deleteSeries(String id) {
    final one = _series(id);
    if (one == null) {
      return notFound();
    }
    if ((one['book_count']! as int) > 0) {
      return jsonAnswer({'error': 'series_not_empty'}, 409);
    }
    series.remove(one);
    return http.Response('', 204);
  }
}

/// A series as `GET /api/v1/series` sends it.
Map<String, Object?> seriesJson(
  int id,
  String name, {
  int bookCount = 1,
  List<int> libraryIds = const [],
  int? startYear,
}) => {
  'id': id,
  'name': name,
  'description': null,
  'start_release_year': startYear,
  'end_release_year': null,
  'book_count': bookCount,
  'library_ids': libraryIds,
};

/// A library as `GET /api/v1/libraries` sends it, without its `series_count`.
Map<String, Object?> libraryJson(
  int id,
  String name, {
  String type = 'books',
  String? description,
}) => {
  'id': id,
  'name': name,
  'library_type': type,
  'description': description,
};
