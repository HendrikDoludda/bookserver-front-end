import 'dart:convert';
import 'dart:io';

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
  FileCatalogStore({this._folder = getApplicationSupportDirectory});

  static const _name = 'catalog.json';

  final Future<Directory> Function() _folder;

  // Two writes at once would interleave in the temporary file; one after another, in the order
  // asked, the newest catalog is the one left on disk.
  Future<void> _writing = Future.value();

  /// The kept catalog; an unreadable one is deleted and counts as none.
  @override
  Future<StoredCatalog?> read() async {
    final file = File('${(await _folder()).path}/$_name');
    if (!await file.exists()) {
      return null;
    }
    try {
      return StoredCatalog.fromJson(jsonDecode(await file.readAsString()));
    } on Exception {
      try {
        await file.delete();
      } on FileSystemException {
        // The next write replaces it.
      }
      return null;
    }
  }

  @override
  Future<void> write(StoredCatalog catalog) {
    final written = _writing
        .then((_) {}, onError: (_) {})
        .then((_) => _write(catalog));
    _writing = written;
    return written;
  }

  Future<void> _write(StoredCatalog catalog) async {
    final folder = await _folder();
    await folder.create(recursive: true);
    final temporary = File('${folder.path}/$_name.tmp');
    await temporary.writeAsString(jsonEncode(catalog.toJson()), flush: true);
    // A rename replaces the old file in one step, so an app killed mid-write never leaves half a
    // catalog behind.
    await temporary.rename('${folder.path}/$_name');
  }
}
