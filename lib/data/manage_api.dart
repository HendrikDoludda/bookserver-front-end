import 'package:bookserver/data/api_client.dart';

/// What a library holds, by the server's name for it.
enum LibraryType {
  books,
  comics,
  magazines,
  documents,
  others;

  /// The type the server calls [value]; one this version of the app doesn't know counts as
  /// [others].
  static LibraryType fromServer(String value) =>
      values.asNameMap()[value] ?? others;
}

/// A library as an admin manages it.
class ManagedLibrary {
  const ManagedLibrary({
    required this.id,
    required this.name,
    required this.type,
    required this.description,
    required this.seriesCount,
  });

  final int id;
  final String name;
  final LibraryType type;
  final String? description;
  final int seriesCount;
}

/// A series as an admin manages it.
class ManagedSeries {
  const ManagedSeries({
    required this.id,
    required this.name,
    required this.description,
    required this.startYear,
    required this.endYear,
    required this.bookCount,
    required this.libraryIds,
  });

  final int id;
  final String name;
  final String? description;
  final int? startYear;
  final int? endYear;
  final int bookCount;

  /// The libraries the series is in; empty for one in no library yet.
  final List<int> libraryIds;
}

/// A new value for a field that can be empty: `Change(null)` clears it, and no `Change` at all
/// leaves it as it is.
final class Change<T> {
  const Change(this.value);

  final T value;
}

/// What an admin changes on the server: libraries, which series they hold, series, and the covers
/// both show.
class ManageApi {
  ManageApi(this._client);

  final ApiClient _client;

  Future<List<ManagedLibrary>> libraries(String sessionToken) =>
      _list('/api/v1/libraries', sessionToken, _library);

  /// Creates a library, holding no series yet, and answers it.
  Future<ManagedLibrary> createLibrary(
    String sessionToken, {
    required String name,
    required LibraryType type,
    String? description,
  }) async => _library(
    await _client.postJson(
      '/api/v1/libraries',
      body: {
        'name': name,
        'library_type': type.name,
        'description': description,
      },
      bearer: sessionToken,
    ),
  );

  /// Changes the fields given; the others stay as they are.
  Future<void> changeLibrary(
    String sessionToken,
    int libraryId, {
    String? name,
    LibraryType? type,
    Change<String?>? description,
  }) async {
    await _client.patchJson(
      '/api/v1/libraries/$libraryId',
      body: {
        'name': ?name,
        'library_type': ?type?.name,
        // A `Change(null)` sends null, which clears the description.
        if (description != null) 'description': description.value,
      },
      bearer: sessionToken,
    );
  }

  /// Deletes the library; its series and books stay.
  Future<void> deleteLibrary(String sessionToken, int libraryId) async {
    await _client.deleteJson(
      '/api/v1/libraries/$libraryId',
      bearer: sessionToken,
    );
  }

  /// Every series by name, each with the libraries it is in.
  Future<List<ManagedSeries>> allSeries(String sessionToken) =>
      _list('/api/v1/series', sessionToken, _series);

  /// Puts the series into the library; one already there stays as it is.
  Future<void> addSeries(
    String sessionToken,
    int libraryId,
    int seriesId,
  ) async {
    await _client.putJson(
      '/api/v1/libraries/$libraryId/series/$seriesId',
      bearer: sessionToken,
    );
  }

  /// Takes the series out of the library; the series and its books stay.
  Future<void> removeSeries(
    String sessionToken,
    int libraryId,
    int seriesId,
  ) async {
    await _client.deleteJson(
      '/api/v1/libraries/$libraryId/series/$seriesId',
      bearer: sessionToken,
    );
  }

  /// Changes the fields given; the others stay as they are.
  Future<void> changeSeries(
    String sessionToken,
    int seriesId, {
    String? name,
    Change<String?>? description,
    Change<int?>? startYear,
    Change<int?>? endYear,
  }) async {
    await _client.patchJson(
      '/api/v1/series/$seriesId',
      body: {
        'name': ?name,
        // A `Change(null)` sends null, which clears the field.
        if (description != null) 'description': description.value,
        if (startYear != null) 'start_release_year': startYear.value,
        if (endYear != null) 'end_release_year': endYear.value,
      },
      bearer: sessionToken,
    );
  }

  /// Deletes a series without books; one with books is refused with `series_not_empty`.
  Future<void> deleteSeries(String sessionToken, int seriesId) async {
    await _client.deleteJson('/api/v1/series/$seriesId', bearer: sessionToken);
  }

  /// The series shows the cover of [bookId], one of its books; one without a cover is refused.
  Future<void> chooseSeriesCover(
    String sessionToken,
    int seriesId,
    int bookId,
  ) async {
    await _client.putJson(
      '/api/v1/series/$seriesId/cover',
      body: {'book_id': bookId},
      bearer: sessionToken,
    );
  }

  /// The series shows its automatic cover again: its first book's.
  Future<void> resetSeriesCover(String sessionToken, int seriesId) async {
    await _client.deleteJson(
      '/api/v1/series/$seriesId/cover',
      bearer: sessionToken,
    );
  }

  /// The library shows the cover [seriesId], one of its series, shows now; the library keeps that
  /// picture when the series' cover changes later.
  Future<void> chooseLibraryCover(
    String sessionToken,
    int libraryId,
    int seriesId,
  ) async {
    await _client.putJson(
      '/api/v1/libraries/$libraryId/cover',
      body: {'series_id': seriesId},
      bearer: sessionToken,
    );
  }

  /// The library shows its automatic cover again: its first series'.
  Future<void> resetLibraryCover(String sessionToken, int libraryId) async {
    await _client.deleteJson(
      '/api/v1/libraries/$libraryId/cover',
      bearer: sessionToken,
    );
  }

  static ManagedLibrary _library(Object? json) => switch (json) {
    {
      'id': final int id,
      'name': final String name,
      'library_type': final String type,
      'description': final String? description,
      'series_count': final int seriesCount,
    } =>
      ManagedLibrary(
        id: id,
        name: name,
        type: LibraryType.fromServer(type),
        description: description,
        seriesCount: seriesCount,
      ),
    _ => throw const FormatException('Not a library.'),
  };

  static ManagedSeries _series(Object? json) => switch (json) {
    {
      'id': final int id,
      'name': final String name,
      'description': final String? description,
      'start_release_year': final int? startYear,
      'end_release_year': final int? endYear,
      'book_count': final int bookCount,
      'library_ids': final List<Object?> libraryIds,
    } =>
      ManagedSeries(
        id: id,
        name: name,
        description: description,
        startYear: startYear,
        endYear: endYear,
        bookCount: bookCount,
        libraryIds: [
          for (final libraryId in libraryIds)
            if (libraryId is int)
              libraryId
            else
              throw const FormatException('Not a library id.'),
        ],
      ),
    _ => throw const FormatException('Not a series.'),
  };

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
