import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// The app's texts by namespace and name, in the shape of
/// `GET /api/v1/locales/{code}/translations`.
class Catalog {
  Catalog._(this.language, this._texts, this._fallback);

  /// Reads a translations answer in [language]; any other shape throws a [FormatException]. A key
  /// the answer lacks is looked up in [fallback] before the key itself is answered.
  factory Catalog.fromJson(
    Object? json, {
    required String language,
    Catalog? fallback,
  }) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('A catalog is an object of namespaces.');
    }
    return Catalog._(language, {
      for (final MapEntry(key: namespace, value: texts) in json.entries)
        namespace: _textsOf(namespace, texts),
    }, fallback);
  }

  static const builtInEnglishAsset = 'assets/translations/en.json';

  static Future<Catalog> loadBuiltInEnglish([AssetBundle? bundle]) async {
    final source = await (bundle ?? rootBundle).loadString(builtInEnglishAsset);
    return Catalog.fromJson(jsonDecode(source), language: 'en');
  }

  /// The code of the catalog's language, such as `en`: [plural] follows its plural rules.
  final String language;

  final Map<String, Map<String, String>> _texts;
  final Catalog? _fallback;

  bool has(String key) => _find(key) != null || (_fallback?.has(key) ?? false);

  /// The text for `namespace.name` — else the fallback's, else the key itself — with each
  /// `{placeholder}` filled from [values]. A placeholder without a value stays as it is.
  String text(String key, [Map<String, Object> values = const {}]) {
    final text = _find(key);
    if (text == null) {
      return _fallback?.text(key, values) ?? key;
    }
    return _fill(text, values);
  }

  /// The text for [count] of `namespace.name`: the form the language's plural rules pick —
  /// `name.one`, `name.few`, `name.other` … — else `name.other`. Without either, the fallback's
  /// form by the fallback's own rules, else the key itself. `{count}` is filled with [count], the
  /// other placeholders from [values].
  String plural(
    String key,
    int count, [
    Map<String, Object> values = const {},
  ]) {
    final form = Intl.pluralLogic(
      count,
      locale: language,
      zero: 'zero',
      one: 'one',
      two: 'two',
      few: 'few',
      many: 'many',
      other: 'other',
      // intl's explicit cases would pick `zero` for 0 in every language; French, for one, uses
      // its `one` form for 0.
      useExplicitNumberCases: false,
    );
    final text = _find('$key.$form') ?? _find('$key.other');
    if (text == null) {
      return _fallback?.plural(key, count, values) ?? key;
    }
    return _fill(text, {...values, 'count': count});
  }

  static String _fill(String text, Map<String, Object> values) {
    if (values.isEmpty) {
      return text;
    }
    return text.replaceAllMapped(
      _placeholder,
      (match) => values[match[1]]?.toString() ?? match[0]!,
    );
  }

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
  /// The text for `namespace.name` from the nearest [CatalogScope], its `{placeholders}` filled
  /// from [values].
  String t(String key, [Map<String, Object> values = const {}]) =>
      CatalogScope.of(this).text(key, values);

  /// The language's form of `namespace.name` for [count] from the nearest [CatalogScope], as
  /// [Catalog.plural] picks it.
  String plural(
    String key,
    int count, [
    Map<String, Object> values = const {},
  ]) => CatalogScope.of(this).plural(key, count, values);
}

// The backend's placeholder, `PLACEHOLDER` in its `translation_seed.rs`: what it checks to match
// between languages is what the app fills.
final _placeholder = RegExp(r'\{([a-z0-9_]+)\}');
