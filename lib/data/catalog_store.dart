import 'dart:io';

import 'package:bookserver/data/json_file.dart';
import 'package:path_provider/path_provider.dart';

/// The catalog last fetched from a server, as the app keeps it between launches.
class StoredCatalog {
  const StoredCatalog({
    required this.server,
    required this.language,
    required this.etag,
    required this.texts,
  });

  factory StoredCatalog.fromJson(Object? json) {
    if (json case {
      'server': String server,
      'language': String language,
      'etag': String? etag,
      'texts': Map<String, Object?> texts,
    }) {
      final origin = Uri.tryParse(server);
      if (origin != null && origin.host.isNotEmpty) {
        return StoredCatalog(
          server: origin,
          language: language,
          etag: etag,
          texts: texts,
        );
      }
    }
    throw const FormatException('Not a stored catalog.');
  }

  final Uri server;
  final String language;

  /// The server's ETag for [texts], or `null` when it sent none.
  final String? etag;

  /// By namespace, as the server answered them.
  final Map<String, Object?> texts;

  Map<String, Object?> toJson() => {
    'server': server.toString(),
    'language': language,
    'etag': etag,
    'texts': texts,
  };
}

/// Where the app keeps its [StoredCatalog] between launches.
abstract interface class CatalogStore {
  Future<StoredCatalog?> read();

  Future<void> write(StoredCatalog catalog);
}

/// Keeps the catalog as `catalog.json` in the app's support folder: nothing in it is secret.
class FileCatalogStore implements CatalogStore {
  FileCatalogStore({
    Future<Directory> Function() folder = getApplicationSupportDirectory,
  }) : _file = JsonFile('catalog.json', folder: folder);

  final JsonFile _file;

  /// The kept catalog; an unreadable one is deleted and counts as none.
  @override
  Future<StoredCatalog?> read() => _file.read(StoredCatalog.fromJson);

  @override
  Future<void> write(StoredCatalog catalog) => _file.write(catalog.toJson());
}
