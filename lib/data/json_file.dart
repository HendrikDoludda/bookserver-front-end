import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A JSON file in the app's support folder — plain text, for nothing secret — written whole or
/// not at all, one write at a time.
class JsonFile {
  JsonFile(this.name, {this._folder = getApplicationSupportDirectory});

  final String name;
  final Future<Directory> Function() _folder;

  // Two writes at once would interleave in the temporary file; one after another, in the order
  // asked, the newest contents are the ones left on disk.
  Future<void> _writing = Future.value();

  /// The file's contents as [parse] reads them; null when there is no file. A file that isn't
  /// JSON, or that [parse] refuses, is deleted and counts as none.
  Future<T?> read<T>(T Function(Object? json) parse) async {
    final file = File('${(await _folder()).path}/$name');
    if (!await file.exists()) {
      return null;
    }
    try {
      return parse(jsonDecode(await file.readAsString()));
    } on Exception {
      try {
        await file.delete();
      } on FileSystemException {
        // The next write replaces it.
      }
      return null;
    }
  }

  /// Replaces the file with [json]. A failed write throws, and keeps the next one from failing.
  Future<void> write(Object? json) {
    final written = _writing
        .then((_) {}, onError: (_) {})
        .then((_) => _write(json));
    _writing = written;
    return written;
  }

  Future<void> _write(Object? json) async {
    final folder = await _folder();
    await folder.create(recursive: true);
    final temporary = File('${folder.path}/$name.tmp');
    await temporary.writeAsString(jsonEncode(json), flush: true);
    // A rename replaces the old file in one step, so an app killed mid-write never leaves half a
    // file behind.
    await temporary.rename('${folder.path}/$name');
  }
}
