import 'dart:ui' show Size;

import 'package:bookserver/data/api_client.dart';

class Library {
  const Library({
    required this.id,
    required this.name,
    required this.seriesCount,
  });

  final int id;
  final String name;

  /// How many series the library holds.
  final int seriesCount;
}

class Series {
  const Series({required this.id, required this.name, required this.bookCount});

  final int id;
  final String name;

  /// How many books the series holds.
  final int bookCount;
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

/// How a book's pages run: right to left, left to right, or top to bottom in one scrolling
/// column.
enum ReadingMode {
  rtl,
  ltr,
  continuous;

  /// The mode the server calls [value]; null for one this version of the app doesn't know.
  static ReadingMode? fromServer(String value) => switch (value) {
    'rtl' => rtl,
    'ltr' => ltr,
    'continuous' => continuous,
    _ => null,
  };
}

/// What the server knows about one book beyond the series' list.
class BookDetails {
  const BookDetails({required this.seriesId, required this.mode});

  /// Null for a book outside any series.
  final int? seriesId;

  /// The mode the signed-in user reads the book in; null for one this version of the app doesn't
  /// know, which a reader reads as its own default.
  final ReadingMode? mode;
}

/// One page of a CBZ or image-folder book.
class BookPage {
  const BookPage({required this.number, this.size});

  /// Counted from 1, as [pagePath] takes it.
  final int number;

  /// The picture's width and height in pixels, as the server read them from its header; null
  /// when it couldn't.
  final Size? size;
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
/// reading order, a book's details and the pages of a book made of images; and the mode a series
/// is read in.
class BrowseApi {
  BrowseApi(this._client);

  final ApiClient _client;

  Future<List<Library>> libraries(String sessionToken) => _list(
    '/api/v1/libraries',
    sessionToken,
    (entry) => switch (entry) {
      {'id': int id, 'name': String name, 'series_count': int count} => Library(
        id: id,
        name: name,
        seriesCount: count,
      ),
      _ => throw const FormatException('Not a library.'),
    },
  );

  Future<List<Series>> seriesOf(int libraryId, String sessionToken) => _list(
    '/api/v1/libraries/$libraryId/series',
    sessionToken,
    (entry) => switch (entry) {
      {'id': int id, 'name': String name, 'book_count': int count} => Series(
        id: id,
        name: name,
        bookCount: count,
      ),
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

  /// The series of the book [bookId] and the mode the signed-in user reads it in.
  Future<BookDetails> book(int bookId, String sessionToken) async {
    final json = await _client.getJson(
      '/api/v1/books/$bookId',
      bearer: sessionToken,
    );
    if (json case {
      'series': final int? series,
      'reading_mode': final String mode,
    }) {
      return BookDetails(seriesId: series, mode: ReadingMode.fromServer(mode));
    }
    throw const FormatException('Not a book.');
  }

  /// Makes [mode] the one the signed-in user reads every book of the series [seriesId] in.
  Future<void> setReadingMode(
    int seriesId,
    ReadingMode mode,
    String sessionToken,
  ) async {
    await _client.putJson(
      '/api/v1/series/$seriesId/reading_mode',
      body: {'mode': mode.name},
      bearer: sessionToken,
    );
  }

  /// The pages of a CBZ or image-folder book, in reading order.
  Future<List<BookPage>> pagesOf(int bookId, String sessionToken) => _list(
    '/api/v1/books/$bookId/pages',
    sessionToken,
    (entry) => switch (entry) {
      {'number': int number, 'width': int width, 'height': int height}
          when width > 0 && height > 0 =>
        BookPage(
          number: number,
          size: Size(width.toDouble(), height.toDouble()),
        ),
      {'number': int number} => BookPage(number: number),
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
