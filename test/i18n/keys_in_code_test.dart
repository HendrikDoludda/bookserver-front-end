import 'dart:convert';
import 'dart:io';

import 'package:bookserver/i18n/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every catalog key written in lib/ has a built-in English text', () {
    final english = jsonDecode(
      File(Catalog.builtInEnglishAsset).readAsStringSync(),
    ) as Map<String, Object?>;
    // A quoted `namespace.name`; keys built at run time, like 'errors.$key', don't match.
    final quotedKey = RegExp(r'''['"]([a-z0-9_]+)\.([a-z0-9_.]+)['"]''');

    final missing = <String>[];
    var found = 0;
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in sources) {
      for (final match in quotedKey.allMatches(file.readAsStringSync())) {
        final texts = english[match[1]];
        if (texts is! Map<String, Object?>) {
          continue; // Not a catalog namespace, so not a key: 'en.json', '1.5'.
        }
        found++;
        if (!texts.containsKey(match[2])) {
          missing.add('${file.path}: ${match[1]}.${match[2]}');
        }
      }
    }

    expect(missing, isEmpty);
    expect(
      found,
      greaterThan(0),
      reason: 'found no keys at all: is the scan broken?',
    );
  });
}
