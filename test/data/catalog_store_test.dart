import 'dart:async';
import 'dart:io';

import 'package:bookserver/data/catalog_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory folder;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('catalog_store_test');
  });
  tearDown(() => folder.delete(recursive: true));

  FileCatalogStore store() => FileCatalogStore(folder: () async => folder);
  File kept() => File('${folder.path}/catalog.json');

  StoredCatalog german({String? etag = '"v1"', String title = 'Anmelden'}) =>
      StoredCatalog(
        server: Uri.parse('https://books.example.ts.net'),
        language: 'de',
        etag: etag,
        texts: {
          'login': {'title': title},
        },
      );

  test('keeps a catalog and reads it back', () async {
    await store().write(german());

    final read = await store().read();

    expect(read?.server, Uri.parse('https://books.example.ts.net'));
    expect(read?.language, 'de');
    expect(read?.etag, '"v1"');
    expect(read?.texts, {
      'login': {'title': 'Anmelden'},
    });
  });

  test('keeps a catalog the server sent without an ETag', () async {
    await store().write(german(etag: null));

    final read = await store().read();
    expect(read, isNotNull);
    expect(read?.etag, isNull);
  });

  test('nothing kept reads as none', () async {
    expect(await store().read(), isNull);
  });

  test('an unreadable file reads as none and is deleted', () async {
    for (final contents in [
      '{"server": "https://books.example.ts.net", "language": "de"',
      '[]',
      '{"server": "https://books.example.ts.net", "language": "de", "etag": null}',
      '{"server": "not an address", "language": "de", "etag": null, "texts": {}}',
      '{"server": "https://books.example.ts.net", "language": 3, "etag": null, "texts": {}}',
    ]) {
      await kept().writeAsString(contents);

      expect(await store().read(), isNull, reason: contents);
      expect(await kept().exists(), isFalse, reason: contents);
    }
  });

  test(
    'a write replaces the kept catalog and leaves no temporary file',
    () async {
      await store().write(german(title: 'Erst'));
      await store().write(german(title: 'Dann'));

      expect((await store().read())?.texts, {
        'login': {'title': 'Dann'},
      });
      expect(folder.listSync().map((entry) => entry.uri.pathSegments.last), [
        'catalog.json',
      ]);
    },
  );

  test('writes asked for at once land in the order asked', () async {
    final keeper = store();
    unawaited(keeper.write(german(title: 'Erst')));
    await keeper.write(german(title: 'Dann'));

    expect((await keeper.read())?.texts, {
      'login': {'title': 'Dann'},
    });
  });

  test('a failed write keeps the next one from failing', () async {
    final inTheWay = File('${folder.path}/in-the-way');
    await inTheWay.writeAsString('a file where the folder should be');
    final blocked = FileCatalogStore(
      folder: () async => Directory(inTheWay.path),
    );

    await expectLater(
      blocked.write(german()),
      throwsA(isA<FileSystemException>()),
    );
    await inTheWay.delete();
    await blocked.write(german(title: 'Dann'));

    expect((await blocked.read())?.texts, {
      'login': {'title': 'Dann'},
    });
  });

  test('a missing folder is made', () async {
    final nested = Directory('${folder.path}/not/yet');
    final keeper = FileCatalogStore(folder: () async => nested);

    await keeper.write(german());

    expect(await keeper.read(), isNotNull);
  });
}
