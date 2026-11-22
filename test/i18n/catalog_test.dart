import 'package:bookserver/i18n/catalog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final catalog = Catalog.fromJson({
    'login': {'title': 'Sign in'},
    'library': {'unread.one': 'One unread', 'unread.other': 'Several unread'},
  }, language: 'en');

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
    }, language: 'en');

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

  group('plural', () {
    /// A catalog in [language] whose `browse.book_count` has [forms].
    Catalog books(String language, Map<String, String> forms) =>
        Catalog.fromJson({
          'browse': {
            for (final MapEntry(key: form, value: text) in forms.entries)
              'book_count.$form': text,
          },
        }, language: language);

    List<String> counted(Catalog catalog, List<int> counts) => [
      for (final count in counts) catalog.plural('browse.book_count', count),
    ];

    test('English and German: one for 1, other for every other count', () {
      for (final language in ['en', 'de']) {
        final catalog = books(language, {
          'one': '{count} book',
          'other': '{count} books',
        });
        expect(counted(catalog, [0, 1, 2, 21]), [
          '0 books',
          '1 book',
          '2 books',
          '21 books',
        ], reason: language);
      }
    });

    test("follows the catalog's language, not English", () {
      final polish = books('pl', {
        'one': '{count} książka',
        'few': '{count} książki',
        'many': '{count} książek',
        'other': '{count} książki',
      });
      expect(counted(polish, [1, 2, 5, 12, 22, 25]), [
        '1 książka',
        '2 książki',
        '5 książek',
        '12 książek',
        '22 książki',
        '25 książek',
      ]);

      final french = books('fr', {
        'one': '{count} livre',
        'other': '{count} livres',
      });
      expect(counted(french, [0, 1, 2]), [
        '0 livre',
        '1 livre',
        '2 livres',
      ], reason: 'French uses its one form for 0 too');
    });

    test('a form the catalog lacks falls back to other', () {
      final polish = books('pl', {
        'one': '{count} książka',
        'other': '{count} książki',
      });
      expect(counted(polish, [1, 5]), ['1 książka', '5 książki']);
    });

    test('a language intl has no rules for takes other for every count', () {
      final unknown = books('qab', {
        'one': '{count} book',
        'other': '{count} books',
      });
      expect(counted(unknown, [1, 2]), ['1 books', '2 books']);
    });

    test('answers the key itself when the catalog lacks it', () {
      final english = books('en', {'one': '{count} book'});
      expect(english.plural('browse.nope', 2), 'browse.nope');
      expect(
        english.plural('browse.book_count', 2),
        'browse.book_count',
        reason: 'neither the form nor other is there',
      );
    });

    test('fills the other placeholders beside the count', () {
      final english = Catalog.fromJson({
        'browse': {
          'in_series.one': '{count} book in {series}',
          'in_series.other': '{count} books in {series}',
        },
      }, language: 'en');

      expect(
        english.plural('browse.in_series', 3, {'series': 'Alpha'}),
        '3 books in Alpha',
      );
      expect(
        english.plural('browse.in_series', 1, {'series': 'Alpha', 'count': 9}),
        '1 book in Alpha',
        reason: 'the count given as such wins',
      );
    });
  });

  group('number', () {
    Catalog inLanguage(String language) =>
        Catalog.fromJson(<String, Object?>{}, language: language);

    test(
      'writes a decimal as the language does, a whole number without a point',
      () {
        expect(inLanguage('en').number(1.5), '1.5');
        expect(inLanguage('de').number(1.5), '1,5');
        expect(inLanguage('de').number(12), '12');
      },
    );

    test('never groups the digits, as a volume or a chapter reads', () {
      expect(inLanguage('en').number(1001), '1001');
      expect(inLanguage('de').number(1001), '1001');
    });

    test('a language intl has no number format for writes as English does', () {
      expect(inLanguage('qaa').number(1.5), '1.5');
    });
  });

  group('fallback', () {
    final english = Catalog.fromJson({
      'login': {'title': 'Sign in', 'subtitle': 'Welcome back'},
      'reader': {'page_of': 'Page {page} of {count}'},
      'browse': {
        'book_count.one': '{count} book',
        'book_count.other': '{count} books',
      },
    }, language: 'en');
    final german = Catalog.fromJson(
      {
        'login': {'title': 'Anmelden'},
      },
      language: 'de',
      fallback: english,
    );

    test("the catalog's own text wins over the fallback's", () {
      expect(german.text('login.title'), 'Anmelden');
    });

    test('a key the catalog lacks comes from the fallback', () {
      expect(german.text('login.subtitle'), 'Welcome back');
      expect(german.has('login.subtitle'), isTrue);
      expect(
        german.text('reader.page_of', {'page': 2, 'count': 9}),
        'Page 2 of 9',
        reason: "the values fill the fallback's text",
      );
    });

    test("a plural the catalog lacks takes the fallback's form, by the fallback's rules", () {
      final french = Catalog.fromJson(
        <String, Object?>{},
        language: 'fr',
        fallback: english,
      );
      expect(
        french.plural('browse.book_count', 0),
        '0 books',
        reason: "French rules would pick one for 0; the English text needs English's",
      );
      expect(french.plural('browse.book_count', 1), '1 book');
    });

    test('a plural the catalog has stays its own', () {
      final translated = Catalog.fromJson(
        {
          'browse': {'book_count.other': '{count} Bücher'},
        },
        language: 'de',
        fallback: english,
      );
      expect(
        translated.plural('browse.book_count', 1),
        '1 Bücher',
        reason: "its other form, not the fallback's one form",
      );
    });

    test('a key in neither answers the key itself', () {
      expect(german.text('nope.title'), 'nope.title');
      expect(german.has('nope.title'), isFalse);
      expect(german.plural('browse.nope', 2), 'browse.nope');
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
          () => Catalog.fromJson(json, language: 'en'),
          throwsFormatException,
          reason: '$json',
        );
      }
    });

    test('takes an empty catalog, which answers every key with itself', () {
      expect(
        Catalog.fromJson(
          <String, Object?>{},
          language: 'en',
        ).text('login.title'),
        'login.title',
      );
    });
  });

  test('the built-in English loads from the app bundle', () async {
    final english = await Catalog.loadBuiltInEnglish();
    for (final key in ['app.name', 'login.title', 'errors.unauthorized']) {
      expect(english.has(key), isTrue, reason: key);
    }
    expect(english.language, 'en');
  });

  group('context.t', () {
    testWidgets('reads the nearest CatalogScope', (tester) async {
      await tester.pumpWidget(_scoped(catalog, const _Shows('login.title')));
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('fills the placeholders from the values', (tester) async {
      final volumes = Catalog.fromJson({
        'browse': {'volume': 'Volume {number}'},
      }, language: 'en');
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

    testWidgets("context.plural picks the scope's form", (tester) async {
      final books = Catalog.fromJson({
        'browse': {
          'book_count.one': '{count} book',
          'book_count.other': '{count} books',
        },
      }, language: 'en');
      await tester.pumpWidget(
        _scoped(
          books,
          Builder(
            builder: (context) => Column(
              children: [
                Text(context.plural('browse.book_count', 1)),
                Text(context.plural('browse.book_count', 4)),
              ],
            ),
          ),
        ),
      );
      expect(find.text('1 book'), findsOneWidget);
      expect(find.text('4 books'), findsOneWidget);
    });

    testWidgets('a new catalog rebuilds even a const widget below it', (
      tester,
    ) async {
      await tester.pumpWidget(_scoped(catalog, const _Shows('login.title')));
      final german = Catalog.fromJson({
        'login': {'title': 'Anmelden'},
      }, language: 'de');

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
