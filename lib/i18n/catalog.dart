import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The app's texts by namespace and name, in the shape of
/// `GET /api/v1/locales/{code}/translations`.
class Catalog {
  Catalog._(this._texts);

  /// Reads a translations answer; any other shape throws a [FormatException].
  factory Catalog.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('A catalog is an object of namespaces.');
    }
    return Catalog._({
      for (final MapEntry(key: namespace, value: texts) in json.entries)
        namespace: _textsOf(namespace, texts),
    });
  }

  static const builtInEnglishAsset = 'assets/translations/en.json';

  static Future<Catalog> loadBuiltInEnglish([AssetBundle? bundle]) async {
    final source = await (bundle ?? rootBundle).loadString(builtInEnglishAsset);
    return Catalog.fromJson(jsonDecode(source));
  }

  final Map<String, Map<String, String>> _texts;

  bool has(String key) => _find(key) != null;

  /// The text for `namespace.name`, or the key itself when the catalog lacks it.
  String text(String key) => _find(key) ?? key;

  String? _find(String key) {
    final dot = key.indexOf('.');
    if (dot < 1) {
      return null;
    }
    return _texts[key.substring(0, dot)]?[key.substring(dot + 1)];
  }

  static Map<String, String> _textsOf(String namespace, Object? texts) {
    if (texts is! Map<String, Object?>) {
      throw FormatException('"$namespace" is not an object of texts.');
    }
    final result = <String, String>{};
    for (final MapEntry(key: name, value: text) in texts.entries) {
      if (text is! String) {
        throw FormatException('"$namespace.$name" is not a text.');
      }
      result[name] = text;
    }
    return result;
  }
}

/// Hands a [Catalog] to every widget below it.
// An InheritedWidget rather than a global: every widget that reads it rebuilds when the catalog
// changes, `const` widgets included, which a global can't trigger.
class CatalogScope extends InheritedWidget {
  const CatalogScope({super.key, required this.catalog, required super.child});

  final Catalog catalog;

  static Catalog of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CatalogScope>();
    if (scope == null) {
      throw FlutterError('No CatalogScope above this widget.');
    }
    return scope.catalog;
  }

  @override
  bool updateShouldNotify(CatalogScope oldWidget) =>
      catalog != oldWidget.catalog;
}

extension CatalogContext on BuildContext {
  /// The text for `namespace.name` from the nearest [CatalogScope].
  String t(String key) => CatalogScope.of(this).text(key);
}
