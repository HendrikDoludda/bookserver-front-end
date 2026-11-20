import 'dart:async';
import 'dart:io';

import 'package:bookserver/data/json_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory folder;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('json_file_test');
  });
  tearDown(() => folder.delete(recursive: true));

  JsonFile file() => JsonFile('kept.json', folder: () async => folder);
  File onDisk() => File('${folder.path}/kept.json');

  Object? asIs(Object? json) => json;

  test('keeps JSON and reads it back', () async {
    await file().write({
      'a': 1,
      'b': ['two'],
    });

    expect(await file().read(asIs), {
      'a': 1,
      'b': ['two'],
    });
  });

  test('no file reads as none, without asking the parser', () async {
    var parsed = false;
    expect(await file().read((json) => parsed = true), isNull);
    expect(parsed, isFalse);
  });

  test('a file that is no JSON reads as none and is deleted', () async {
    await onDisk().writeAsString('{"a": 1');

    expect(await file().read(asIs), isNull);
    expect(await onDisk().exists(), isFalse);
  });

  test('a file the parser refuses reads as none and is deleted', () async {
    await onDisk().writeAsString('[]');

    expect(
      await file().read<int>(
        (json) => throw const FormatException('Not a number.'),
      ),
      isNull,
    );
    expect(await onDisk().exists(), isFalse);
  });

  test('a write replaces the file and leaves no temporary one', () async {
    await file().write('first');
    await file().write('then');

    expect(await file().read(asIs), 'then');
    expect(folder.listSync().map((entry) => entry.uri.pathSegments.last), [
      'kept.json',
    ]);
  });

  test('writes asked for at once land in the order asked', () async {
    final kept = file();
    unawaited(kept.write('first'));
    await kept.write('then');

    expect(await kept.read(asIs), 'then');
  });

  test('a failed write keeps the next one from failing', () async {
    final inTheWay = File('${folder.path}/in-the-way');
    await inTheWay.writeAsString('a file where the folder should be');
    final blocked = JsonFile(
      'kept.json',
      folder: () async => Directory(inTheWay.path),
    );

    await expectLater(
      blocked.write('first'),
      throwsA(isA<FileSystemException>()),
    );
    await inTheWay.delete();
    await blocked.write('then');

    expect(await blocked.read(asIs), 'then');
  });

  test('a missing folder is made', () async {
    final nested = JsonFile(
      'kept.json',
      folder: () async => Directory('${folder.path}/not/yet'),
    );

    await nested.write('kept');

    expect(await nested.read(asIs), 'kept');
  });
}
