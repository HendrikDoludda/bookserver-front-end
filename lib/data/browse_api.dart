import 'package:bookserver/data/api_client.dart';

class Library {
  const Library({required this.id, required this.name});

  final int id;
  final String name;
}

class Series {
  const Series({required this.id, required this.name});

  final int id;
  final String name;
}

/// What kind of file a book is, which decides the reader that opens it.
enum BookFormat {
  pdf,
  epub,
  cbz,
  imageComic,

  /// A format this version of the app has no reader for.
  unsupported;

  static BookFormat fromServer(String value) => switch (value) {
    'pdf' => pdf,
    'epub' => epub,
    'cbz' => cbz,
    'image_comic' => imageComic,
    _ => unsupported,
  };
}

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.format,
    this.volume,
    this.chapter,
  });

  final int id;
  final String title;
  final BookFormat format;
  final int? volume;
  final int? chapter;
}

/// What a cover belongs to. A series or library without a cover of its own shows its first
/// book's.
enum CoverKind { book, series, library }

/// Where the cover of the [kind] with [id] is.
String coverPath(CoverKind kind, int id) => '/api/v1/covers/${kind.name}/$id';

/// Where the file of the book [bookId] is, which the server also serves in byte ranges.
String bookFilePath(int bookId) => '/api/v1/books/$bookId/file';

/// Where page [number] of the CBZ or image-folder book [bookId] is, counted from 1.
String pagePath(int bookId, int number) =>
    '/api/v1/books/$bookId/pages/$number';

/// The way from the libraries to a book: the libraries, a library's series, a series' books in
/// reading order, and the pages of a book made of images.
class BrowseApi {
  BrowseApi(this._client);

  final ApiClient _client;

  Future<List<Library>> libraries(String sessionToken) => _list(
    '/api/v1/libraries',
    sessionToken,
    (entry) => switch (entry) {
      {'id': int id, 'name': String name} => Library(id: id, name: name),
      _ => throw const FormatException('Not a library.'),
    },
  );

  Future<List<Series>> seriesOf(int libraryId, String sessionToken) => _list(
    '/api/v1/libraries/$libraryId/series',
    sessionToken,
    (entry) => switch (entry) {
      {'id': int id, 'name': String name} => Series(id: id, name: name),
      _ => throw const FormatException('Not a series.'),
    },
  );

  Future<List<Book>> booksOf(int seriesId, String sessionToken) => _list(
    '/api/v1/series/$seriesId/books',
    sessionToken,
    (entry) => switch (entry) {
      {
        'id': int id,
        'title': String title,
        'format': String format,
        'volume_number': int? volume,
        'chapter_number': int? chapter,
      } =>
        Book(
          id: id,
          title: title,
          format: BookFormat.fromServer(format),
          volume: volume,
          chapter: chapter,
        ),
      _ => throw const FormatException('Not a book.'),
    },
  );

  /// The numbers of a CBZ or image-folder book's pages, in reading order.
  Future<List<int>> pagesOf(int bookId, String sessionToken) => _list(
    '/api/v1/books/$bookId/pages',
    sessionToken,
    (entry) => switch (entry) {
      {'number': int number} => number,
      _ => throw const FormatException('Not a page.'),
    },
  );

  Future<List<T>> _list<T>(
    String path,
    String sessionToken,
    T Function(Object? entry) read,
  ) async {
    final json = await _client.getJson(path, bearer: sessionToken);
    if (json is! List<Object?>) {
      throw FormatException('Not a list: $path');
    }
    return [for (final entry in json) read(entry)];
  }
}
