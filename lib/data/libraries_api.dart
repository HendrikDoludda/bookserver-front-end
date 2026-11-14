import 'package:bookserver/data/api_client.dart';

class Library {
  const Library({required this.id, required this.name});

  final int id;
  final String name;
}

class LibrariesApi {
  LibrariesApi(this._client);

  final ApiClient _client;

  Future<List<Library>> list(String sessionToken) async {
    final json = await _client.getJson(
      '/api/v1/libraries',
      bearer: sessionToken,
    );
    if (json is! List<Object?>) {
      throw const FormatException('Not a list of libraries.');
    }
    return [
      for (final entry in json)
        if (entry case {'id': int id, 'name': String name})
          Library(id: id, name: name)
        else
          throw const FormatException('Not a library.'),
    ];
  }
}
