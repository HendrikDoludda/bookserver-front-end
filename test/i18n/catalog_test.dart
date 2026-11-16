import 'package:bookserver/i18n/catalog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final catalog = Catalog.fromJson({
    'login': {'title': 'Sign in'},
    'library': {'unread.one': 'One unread', 'unread.other': 'Several unread'},
  });

  group('text', () {
    test('finds a text by namespace and name', () {
      expect(catalog.text('login.title'), 'Sign in');
      expect(catalog.has('login.title'), isTrue);
    });

    test('splits at the first dot, so a name keeps its own dots', () {
      expect(catalog.text('library.unread.one'), 'One unread');
      expect(catalog.text('library.unread.other'), 'Several unread');
    });

    test('answers the key itself when the catalog lacks it', () {
      for (final key in [
        'login.subtitle',
        'nope.title',
        'login',
        '.title',
        'login.',
        '',
      ]) {
        expect(catalog.text(key), key, reason: key);
        expect(catalog.has(key), isFalse, reason: key);
      }
    });
  });

  group('text with values', () {
    final reader = Catalog.fromJson({
      'reader': {
        'page_of': 'Page {page} of {count}',
        'both': '{count} pages, {count} in all',
        'odd': 'Keep {page} and {Page} and {page-1}',
      },
    });

    test('fills each placeholder from its value', () {
      expect(
        reader.text('reader.page_of', {'page': 2, 'count': 10}),
        'Page 2 of 10',
      );
      expect(
        reader.text('reader.both', {'count': 12}),
        '12 pages, 12 in all',
        reason: 'a placeholder used twice',
      );
    });

    test('leaves a placeholder without a value as it is', () {
      expect(reader.text('reader.page_of'), 'Page {page} of {count}');
      expect(reader.text('reader.page_of', {'page': 2}), 'Page 2 of {count}');
      expect(
        reader.text('reader.page_of', {'pages': 2, 'Page': 3}),
        'Page {page} of {count}',
      );
    });

    test("fills only the backend's placeholder shape, and only once", () {
      expect(
        reader.text('reader.odd', {'page': 1, 'Page': 2, 'page-1': 3}),
        'Keep 1 and {Page} and {page-1}',
      );
      expect(
        reader.text('reader.page_of', {'page': '{count}', 'count': 10}),
        'Page {count} of 10',
        reason: 'a value is not filled again',
      );
    });

    test('a key the catalog lacks stays the key', () {
      expect(reader.text('reader.nope', {'page': 1}), 'reader.nope');
    });
  });

  group('fromJson', () {
    test('refuses anything but an object of namespaces of texts', () {
      final shapes = <Object?>[
        null,
        'Sign in',
        ['login'],
        {'login': 'Sign in'},
        {
          'login': {'title': 3},
        },
        {
          'login': {'title': null},
        },
        {
          'login': {
            'title': {'nested': 'Sign in'},
          },
        },
      ];
      for (final json in shapes) {
        expect(
          () => Catalog.fromJson(json),
          throwsFormatException,
          reason: '$json',
        );
      }
    });

    test('takes an empty catalog, which answers every key with itself', () {
      expect(
        Catalog.fromJson(<String, Object?>{}).text('login.title'),
        'login.title',
      );
    });
  });

  test('the built-in English loads from the app bundle', () async {
    final english = await Catalog.loadBuiltInEnglish();
    for (final key in ['app.name', 'login.title', 'errors.unauthorized']) {
      expect(english.has(key), isTrue, reason: key);
    }
  });

  group('context.t', () {
    testWidgets('reads the nearest CatalogScope', (tester) async {
      await tester.pumpWidget(_scoped(catalog, const _Shows('login.title')));
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('fills the placeholders from the values', (tester) async {
      final volumes = Catalog.fromJson({
        'browse': {'volume': 'Volume {number}'},
      });
      await tester.pumpWidget(
        _scoped(
          volumes,
          Builder(
            builder: (context) =>
                Text(context.t('browse.volume', {'number': 3})),
          ),
        ),
      );
      expect(find.text('Volume 3'), findsOneWidget);
    });

    testWidgets('a new catalog rebuilds even a const widget below it', (
      tester,
    ) async {
      await tester.pumpWidget(_scoped(catalog, const _Shows('login.title')));
      final german = Catalog.fromJson({
        'login': {'title': 'Anmelden'},
      });

      await tester.pumpWidget(_scoped(german, const _Shows('login.title')));

      expect(find.text('Anmelden'), findsOneWidget);
    });

    testWidgets('fails loudly without a CatalogScope above it', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: _Shows('login.title'),
        ),
      );
      expect(tester.takeException(), isA<FlutterError>());
    });
  });
}

Widget _scoped(Catalog catalog, Widget child) => CatalogScope(
  catalog: catalog,
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);

class _Shows extends StatelessWidget {
  const _Shows(this.textKey);

  final String textKey;

  @override
  Widget build(BuildContext context) => Text(context.t(textKey));
}
