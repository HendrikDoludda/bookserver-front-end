import 'package:bookserver/data/api_client.dart';
import 'package:bookserver/data/browse_api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server.dart';

void main() {
  final origin = Uri.parse('https://books.example.ts.net');
  BrowseApi apiFor(FakeServer server) =>
      BrowseApi(ApiClient(server.client, origin));

  /// A book exactly as `GET /api/v1/series/{id}/books` sends one.
  Map<String, Object?> bookJson({
    int id = 7,
    String title = 'The Long Road',
    String format = 'cbz',
    int? volume = 1,
    int? chapter,
  }) => {
    'id': id,
    'title': title,
    'author': 'Unknown Author',
    'format': format,
    'tags': <String>[],
    'description': null,
    'language': null,
    'page_count': null,
    'series': 2,
    'volume_number': volume,
    'chapter_number': chapter,
    'page_number': null,
    'last_modified': null,
    'file_size': null,
  };

  void expectGet(FakeServer server, String path) {
    final request = server.requests.single;
    expect(request.method, 'GET');
    expect(request.url.path, path);
    expect(request.headers['authorization'], 'Bearer session-1');
  }

  test('lists the libraries', () async {
    final server = FakeServer(
      (_) async => jsonAnswer([
        {
          'id': 1,
          'name': '/books',
          'library_type': 'Books',
          'cover_image': null,
          'description': null,
          'series_count': 12,
        },
        {
          'id': 2,
          'name': '/manga',
          'library_type': 'Comics',
          'cover_image': null,
          'description': null,
          'series_count': 0,
        },
      ]),
    );

    final libraries = await apiFor(server).libraries('session-1');

    expect(
      [
        for (final library in libraries)
          (library.id, library.name, library.seriesCount),
      ],
      [(1, '/books', 12), (2, '/manga', 0)],
    );
    expectGet(server, '/api/v1/libraries');
  });

  test("lists a library's series", () async {
    final server = FakeServer(
      (_) async => jsonAnswer([
        {
          'id': 4,
          'name': 'alpha',
          'description': null,
          'cover_image': null,
          'start_release_year': null,
          'end_release_year': null,
          'book_count': 7,
        },
      ]),
    );

    final series = await apiFor(server).seriesOf(3, 'session-1');

    expect(
      [for (final one in series) (one.id, one.name, one.bookCount)],
      [(4, 'alpha', 7)],
    );
    expectGet(server, '/api/v1/libraries/3/series');
  });

  test("lists a series' books with their format, volume and chapter", () async {
    final server = FakeServer(
      (_) async => jsonAnswer([
        bookJson(id: 7, volume: 1),
        bookJson(id: 8, volume: 2, chapter: 12, format: 'image_comic'),
        bookJson(id: 9, title: 'Extras', volume: null, format: 'pdf'),
      ]),
    );

    final books = await apiFor(server).booksOf(2, 'session-1');

    expect(
      [
        for (final book in books)
          (book.id, book.title, book.format, book.volume, book.chapter),
      ],
      [
        (7, 'The Long Road', BookFormat.cbz, 1, null),
        (8, 'The Long Road', BookFormat.imageComic, 2, 12),
        (9, 'Extras', BookFormat.pdf, null, null),
      ],
    );
    expectGet(server, '/api/v1/series/2/books');
  });

  test('reads every format the server names, any other as unsupported', () {
    for (final (value, format) in [
      ('pdf', BookFormat.pdf),
      ('epub', BookFormat.epub),
      ('cbz', BookFormat.cbz),
      ('image_comic', BookFormat.imageComic),
      ('none', BookFormat.unsupported),
      ('mobi', BookFormat.unsupported),
    ]) {
      expect(BookFormat.fromServer(value), format, reason: value);
    }
  });

  test("lists the numbers of a book's pages", () async {
    final server = FakeServer(
      (_) async => jsonAnswer([
        {'number': 1},
        {'number': 2},
        {'number': 3},
      ]),
    );

    expect(await apiFor(server).pagesOf(5, 'session-1'), [1, 2, 3]);
    expectGet(server, '/api/v1/books/5/pages');
  });

  test('names the cover of a book, a series and a library', () {
    expect(coverPath(CoverKind.book, 1), '/api/v1/covers/book/1');
    expect(coverPath(CoverKind.series, 2), '/api/v1/covers/series/2');
    expect(coverPath(CoverKind.library, 3), '/api/v1/covers/library/3');
  });

  test("names a book's page by its number", () {
    expect(pagePath(5, 1), '/api/v1/books/5/pages/1');
    expect(pagePath(5, 12), '/api/v1/books/5/pages/12');
  });

  test('an empty list is empty', () async {
    final server = FakeServer((_) async => jsonAnswer([]));
    final api = apiFor(server);
    expect(await api.libraries('session-1'), isEmpty);
    expect(await api.seriesOf(1, 'session-1'), isEmpty);
    expect(await api.booksOf(1, 'session-1'), isEmpty);
    expect(await api.pagesOf(1, 'session-1'), isEmpty);
  });

  test('refuses an answer of another shape', () async {
    final calls = <String, Future<Object?> Function(BrowseApi api)>{
      'libraries': (api) => api.libraries('session-1'),
      'series': (api) => api.seriesOf(1, 'session-1'),
      'books': (api) => api.booksOf(1, 'session-1'),
      'pages': (api) => api.pagesOf(1, 'session-1'),
    };
    final wrong = <String, List<Object?>>{
      'libraries': [
        {'id': '1', 'name': '/books', 'series_count': 1},
        {'id': 1, 'series_count': 1},
        {'id': 1, 'name': '/books'},
        {'id': 1, 'name': '/books', 'series_count': '1'},
      ],
      'series': [
        {'id': 1, 'name': null, 'book_count': 1},
        {'name': 'alpha', 'book_count': 1},
        {'id': 1, 'name': 'alpha'},
        {'id': 1, 'name': 'alpha', 'book_count': null},
      ],
      'books': [
        {...bookJson(), 'volume_number': '1'},
        {...bookJson(), 'format': 3},
        {...bookJson()}..remove('chapter_number'),
      ],
      'pages': [
        {'number': '1'},
        {'page': 1},
      ],
    };
    for (final MapEntry(key: name, value: call) in calls.entries) {
      final answers = <Object?>[
        {'not': 'a list'},
        for (final entry in wrong[name]!) [entry],
      ];
      for (final answer in answers) {
        final server = FakeServer((_) async => jsonAnswer(answer));
        await expectLater(
          call(apiFor(server)),
          throwsFormatException,
          reason: '$name: $answer',
        );
      }
    }
  });
}
