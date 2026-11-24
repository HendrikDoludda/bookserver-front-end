import 'dart:convert';
import 'dart:math' as math;

import 'package:bookserver/data/epub_book.dart';
import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart' as css;
import 'package:flutter/painting.dart';
import 'package:xml/xml.dart';

/// A page of a fixed-layout book as the book lays it out, in CSS pixels: its size, what shows
/// behind it, its pictures and its lines of text, each at its own spot.
class FixedPage {
  const FixedPage({
    required this.size,
    required this.background,
    required this.images,
    required this.lines,
    required this.fonts,
  });

  /// Reads page [index] of the book [styles] belongs to. A page that isn't well-formed XHTML,
  /// or that gives no size, throws a [FormatException].
  factory FixedPage.parse(BookStyles styles, int index) =>
      _PageReader(styles, styles.book.chapters[index]).read();

  final Size size;
  final PageBackground background;

  /// In the order the page lists them; drawn above the background and below the text.
  final List<PageImage> images;

  /// In the order the page lists them.
  final List<TextLine> lines;

  /// The font files of the families the page's stylesheets declare: family → paths in the
  /// archive.
  final Map<String, List<String>> fonts;
}

/// What a page shows behind its text.
class PageBackground {
  const PageBackground({
    this.color,
    this.image,
    this.fit = BoxFit.none,
    this.alignment = Alignment.topLeft,
  });

  final Color? color;

  /// The picture's path in the archive.
  final String? image;

  final BoxFit fit;
  final Alignment alignment;
}

/// A picture an `<img>` puts on the page, placed by its top or its bottom left corner.
class PageImage {
  const PageImage({
    required this.path,
    required this.position,
    this.placedByBottom = false,
    this.width,
    this.height,
    this.enclosing = LineTransform.identity,
  });

  /// The picture's path in the archive.
  final String path;

  /// Where its top left corner sits on the page — its bottom left corner when [placedByBottom].
  final Offset position;

  final bool placedByBottom;

  /// Null for the picture's own.
  final double? width;
  final double? height;

  /// The transforms of the boxes around it, as one, in the page's coordinates.
  final LineTransform enclosing;
}

/// A line of text, placed by its top or its bottom left corner.
class TextLine {
  const TextLine({
    required this.position,
    required this.style,
    required this.runs,
    this.placedByBottom = false,
    this.transform = LineTransform.identity,
    this.origin = LineOrigin.center,
    this.enclosing = LineTransform.identity,
  });

  /// Where its top left corner sits on the page — its bottom left corner when [placedByBottom].
  final Offset position;

  /// Whether the book places the line by its bottom edge, which then stays where it is whatever
  /// height the line's text gives it.
  final bool placedByBottom;

  /// The line's own text style: as in CSS, the line is at least as tall as its line height,
  /// whatever the styles of its runs.
  final RunStyle style;

  /// How the line is scaled and turned, around [origin].
  final LineTransform transform;

  final LineOrigin origin;

  /// The transforms of the boxes around it, as one, in the page's coordinates: applied after its
  /// own.
  final LineTransform enclosing;

  final List<TextRun> runs;
}

/// A 2D transform as CSS's `matrix(a, b, c, d, e, f)` writes it: it takes the point (x, y) to
/// (a·x + c·y + e, b·x + d·y + f).
class LineTransform {
  const LineTransform(this.a, this.b, this.c, this.d, this.e, this.f);

  /// Clockwise by [angle] radians.
  LineTransform.rotation(double angle)
    : this(
        math.cos(angle),
        math.sin(angle),
        -math.sin(angle),
        math.cos(angle),
        0,
        0,
      );

  const LineTransform.translation(double dx, double dy)
    : this(1, 0, 0, 1, dx, dy);

  static const identity = LineTransform(1, 0, 0, 1, 0, 0);

  bool get isIdentity =>
      a == 1 && b == 0 && c == 0 && d == 1 && e == 0 && f == 0;

  final double a;
  final double b;
  final double c;
  final double d;
  final double e;
  final double f;

  /// [other] first, then this: CSS applies a list of transforms from its last one.
  LineTransform operator *(LineTransform other) => LineTransform(
    a * other.a + c * other.b,
    b * other.a + d * other.b,
    a * other.c + c * other.d,
    b * other.c + d * other.d,
    a * other.e + c * other.f + e,
    b * other.e + d * other.f + f,
  );
}

/// The point a line is transformed around: [alignment] within the line's box, moved by [offset].
class LineOrigin {
  const LineOrigin(this.alignment, [this.offset = Offset.zero]);

  /// CSS's starting value.
  static const center = LineOrigin(Alignment.center);

  final Alignment alignment;
  final Offset offset;
}

/// A stretch of a line in one style.
class TextRun {
  const TextRun(this.text, this.style, {this.link, this.marginLeft = 0});

  final String text;
  final RunStyle style;

  /// The page a tap on the run turns to, as an index into [EpubBook.chapters].
  final int? link;

  /// The `margin-left` of the elements it starts, in CSS pixels: how far it sits from the text
  /// before it.
  final double marginLeft;
}

/// How a run's text looks.
class RunStyle {
  // CSS's starting values: 16 px is its `medium` font size.
  const RunStyle({
    this.fontFamily,
    this.fontSize = 16,
    this.fontWeight = FontWeight.w400,
    this.italic = false,
    this.lineHeight,
    this.color = const Color(0xFF000000),
    this.letterSpacing = 0,
    this.underline = false,
  });

  /// As the book names it; [FixedPage.fonts] has its files when the book brings them.
  final String? fontFamily;

  final double fontSize;
  final FontWeight fontWeight;
  final bool italic;

  /// In CSS pixels; null leaves it to the font.
  final double? lineHeight;

  final Color color;
  final double letterSpacing;
  final bool underline;
}

/// The stylesheets of a fixed-layout book, each read and parsed the first time a page links it.
class BookStyles {
  BookStyles(this.book);

  final EpubBook book;
  final _sheets = <String, _StyleSheet?>{};

  /// The stylesheet at [path]; null when the book has none there, and while it is being parsed,
  /// so an `@import` that leads back to it brings in nothing.
  _StyleSheet? _sheet(String path) {
    if (_sheets.containsKey(path)) {
      return _sheets[path];
    }
    _sheets[path] = null;
    final bytes = book.read(path);
    return _sheets[path] = bytes == null
        ? null
        : _StyleSheet.parse(
            utf8.decode(bytes, allowMalformed: true),
            path,
            this,
          );
  }
}

/// Reads one page: which rules apply to each element, what its text inherits, and where it sits.
class _PageReader {
  _PageReader(this._styles, this._path);

  final BookStyles _styles;
  final String _path;
  late final List<_StyleSheet> _sheets;
  late final Size _size;
  final _own = Map<XmlElement, _Own>.identity();
  final _textStyles = Map<XmlElement, RunStyle>.identity();
  final _images = <PageImage>[];
  final _lines = <TextLine>[];

  FixedPage read() {
    // XHTML read as XML: an HTML parser puts what follows a self-closing `<div/>` inside it, which
    // would move it by that div's offset. HTML's entity names still count, `&nbsp;` among them.
    final document = XmlDocument.parse(
      utf8.decode(_styles.book.read(_path)!, allowMalformed: true),
      entityMapping: const XmlDefaultEntityMapping.html5(),
    );
    final head = _child(document.rootElement, 'head');
    final body =
        _child(document.rootElement, 'body') ??
        (throw FormatException('The page $_path has no body.'));
    _sheets = [
      for (final element in head?.childElements ?? const <XmlElement>[])
        ?_sheetOf(element),
    ];
    final box = body.childElements.firstOrNull;
    _size =
        _viewport(head) ??
        (box == null ? null : _boxSize(box)) ??
        (throw FormatException('The page $_path gives no size.'));
    _addLines(
      body,
      (origin: Offset.zero, bottom: _size.height, height: _size.height),
      LineTransform.identity,
      null,
    );
    return FixedPage(
      size: _size,
      background: _background([?box, body]),
      images: _images,
      lines: _lines,
      fonts: {
        for (final sheet in _sheets)
          for (final MapEntry(key: family, value: files) in sheet.fonts.entries)
            family: files,
      },
    );
  }

  /// The stylesheet [element] links, or holds as a `<style>` of this page alone.
  _StyleSheet? _sheetOf(XmlElement element) {
    switch (element.localName) {
      case 'link'
          when _words(element.getAttribute('rel') ?? '').contains('stylesheet'):
        if (element.getAttribute('href') case final href?) {
          if (_resolve(href, _path) case final path?) {
            return _styles._sheet(path);
          }
        }
      case 'style':
        return _StyleSheet.parse(element.innerText, _path, _styles);
    }
    return null;
  }

  /// The size `<meta name="viewport" content="width=…, height=…">` gives the page.
  Size? _viewport(XmlElement? head) {
    for (final meta in head?.childElements ?? const <XmlElement>[]) {
      if (meta.localName == 'meta' && meta.getAttribute('name') == 'viewport') {
        final content = meta.getAttribute('content') ?? '';
        if ((
              _viewportValue(content, 'width'),
              _viewportValue(content, 'height'),
            )
            case (final width?, final height?)) {
          return Size(width, height);
        }
      }
    }
    return null;
  }

  Size? _boxSize(XmlElement box) {
    final own = _ownOf(box);
    final em = _textStyleOf(box).fontSize;
    double? side(String property) => _winning(
      own,
      property,
      (value) => _positive(_length(value.text, em: em)),
    );
    return switch ((side('width'), side('height'))) {
      (final width?, final height?) => Size(width, height),
      _ => null,
    };
  }

  /// The colour of the first of [boxes] that has one that can be seen; the picture of the first
  /// that has one.
  PageBackground _background(List<XmlElement> boxes) {
    final color = boxes
        .map(
          (box) => _winning(
            _ownOf(box),
            'background-color',
            (value) => _color(value.text),
          ),
        )
        .nonNulls
        // CSS draws a fully transparent background as none: the box under it shows through.
        .where((color) => color.a > 0)
        .firstOrNull;
    for (final box in boxes) {
      final own = _ownOf(box);
      final image = _winning(own, 'background-image', _image);
      if (image?.path case final path?) {
        return PageBackground(
          color: color,
          image: path,
          fit:
              _winning(own, 'background-size', (value) => _fit(value.text)) ??
              BoxFit.none,
          alignment:
              _winning(
                own,
                'background-position',
                (value) => _alignment(value.text),
              ) ??
              Alignment.topLeft,
        );
      }
    }
    return PageBackground(color: color);
  }

  /// Adds the pictures and lines inside [element], or [element] itself, to the page: an `<img>`
  /// is a picture; an element with a `left`, `top` or `bottom` and none inside it is a line; one
  /// with some inside is the box they are placed in, and its `transform` theirs. [element] is
  /// placed in [frame], inside boxes whose transforms make [enclosing]. Answers whether
  /// [element] is or holds such an element.
  bool _addLines(
    XmlElement element,
    _Frame frame,
    LineTransform enclosing,
    int? link,
  ) {
    final own = _ownOf(element);
    final em = _textStyleOf(element).fontSize;
    double? length(String property, double percentOf) => _winning(
      own,
      property,
      (value) => _length(value.text, em: em, percentOf: percentOf),
    );
    final left = length('left', _size.width);
    final top = length('top', _size.height);
    final bottom = length('bottom', frame.height);
    final placed = left != null || top != null || bottom != null;
    // CSS places a box by its top when it gives both.
    final byBottom = top == null && bottom != null;
    final position = Offset(
      frame.origin.dx + (left ?? 0),
      byBottom ? frame.bottom - bottom : frame.origin.dy + (top ?? 0),
    );
    final width = _nonNegative(length('width', _size.width));
    final height = _nonNegative(length('height', frame.height));
    if (element.localName == 'img') {
      if (element.getAttribute('src') case final source?) {
        if (_resolve(source, _path) case final path?) {
          _images.add(
            PageImage(
              path: path,
              position: position,
              placedByBottom: byBottom,
              width: width ?? _attributeLength(element.getAttribute('width')),
              height:
                  height ?? _attributeLength(element.getAttribute('height')),
              enclosing: enclosing,
            ),
          );
        }
      }
      return placed;
    }
    final linkHere = _linkOf(element) ?? link;
    var inner = frame;
    if (placed) {
      final origin = byBottom ? position - Offset(0, height ?? 0) : position;
      // CSS makes a positioned box with no height as tall as its content, and content that is
      // placed itself takes no room.
      final boxHeight = height ?? (_positioned(own) ? 0.0 : null);
      inner = boxHeight == null
          ? (origin: origin, bottom: frame.bottom, height: frame.height)
          : (origin: origin, bottom: origin.dy + boxHeight, height: boxHeight);
    }
    final transform =
        _winning(own, 'transform', (value) => _transform(value.text)) ??
        LineTransform.identity;
    final origin =
        _winning(own, 'transform-origin', (value) => _origin(value.text, em)) ??
        LineOrigin.center;
    var inside = enclosing;
    if (!transform.isIdentity) {
      // A box without a size is measured as none: its origin falls on its top left.
      final point =
          inner.origin +
          origin.alignment.alongSize(Size(width ?? 0, height ?? 0)) +
          origin.offset;
      inside =
          enclosing *
          LineTransform.translation(point.dx, point.dy) *
          transform *
          LineTransform.translation(-point.dx, -point.dy);
    }
    var holdsPlaced = false;
    for (final child in element.childElements) {
      holdsPlaced = _addLines(child, inner, inside, linkHere) || holdsPlaced;
    }
    if (placed && !holdsPlaced) {
      final runs = _runs(element, linkHere);
      if (runs.isNotEmpty) {
        _lines.add(
          TextLine(
            position: position,
            placedByBottom: byBottom,
            style: _textStyleOf(element),
            transform: transform,
            origin: origin,
            enclosing: enclosing,
            runs: runs,
          ),
        );
      }
    }
    return placed || holdsPlaced;
  }

  List<TextRun> _runs(XmlElement line, int? link) {
    final runs = <TextRun>[];
    // The margins of the elements entered since the last text, which the next text keeps.
    var margin = 0.0;
    void collect(XmlElement element, int? link) {
      final style = _textStyleOf(element);
      for (final node in element.children) {
        switch (node) {
          case XmlText():
            runs.add(
              TextRun(node.value, style, link: link, marginLeft: margin),
            );
            margin = 0;
          case XmlElement():
            margin +=
                _winning(
                  _ownOf(node),
                  'margin-left',
                  (value) =>
                      _length(value.text, em: _textStyleOf(node).fontSize),
                ) ??
                0;
            collect(node, _linkOf(node) ?? link);
          default:
        }
      }
    }

    collect(line, link);
    return _collapsed(runs);
  }

  /// The page an `<a>` leads to, when it is one of the book's pages.
  int? _linkOf(XmlElement element) {
    if (element.localName != 'a') {
      return null;
    }
    final target = switch (element.getAttribute('href')) {
      final href? => _resolve(href, _path),
      null => null,
    };
    final index = _styles.book.chapters.indexOf(target ?? '');
    return index < 0 ? null : index;
  }

  RunStyle _textStyleOf(XmlElement element) =>
      _textStyles[element] ??= _inherit(switch (element.parentElement) {
        final parent? => _textStyleOf(parent),
        null => const RunStyle(),
      }, _ownOf(element));

  _Own _ownOf(XmlElement element) => _own[element] ??= _cascade(element);

  /// [element]'s declarations from the rules that match it — by specificity, then in the order
  /// the page links the stylesheets and they list the rules — then its `style` attribute.
  _Own _cascade(XmlElement element) {
    final tag = element.localName.toLowerCase();
    final id = element.getAttribute('id');
    final classes = _words(element.getAttribute('class') ?? '').toSet();
    final matched = [
      for (final (sheetIndex, sheet) in _sheets.indexed)
        for (final rule in sheet.candidates(tag, id, classes))
          if (rule.selector.matches(tag, id, classes)) (sheetIndex, rule),
    ];
    matched.sort((a, b) {
      final (sheetA, ruleA) = a;
      final (sheetB, ruleB) = b;
      return switch (ruleA.selector.specificity.compareTo(
        ruleB.selector.specificity,
      )) {
        0 when sheetA != sheetB => sheetA.compareTo(sheetB),
        0 => ruleA.order.compareTo(ruleB.order),
        final bySpecificity => bySpecificity,
      };
    });
    final own = <String, List<_Value>>{};
    void add(List<(String, _Value)> declarations) {
      for (final (property, value) in declarations) {
        (own[property] ??= []).add(value);
      }
    }

    for (final (_, rule) in matched) {
      add(rule.declarations);
    }
    if (element.getAttribute('style') case final style?) {
      add(_inlineDeclarations(style, _path));
    }
    return own;
  }
}

/// What the elements inside a placed box are placed from: the box's top left on the page, and the
/// bottom edge and height of the nearest box around them that gives its height or is `position:
/// absolute` or `fixed` (0 tall without one) — the page's when none is, as CSS places a box with
/// no placed box around it on the page.
typedef _Frame = ({Offset origin, double bottom, double height});

/// Whether [own] places its element out of the flow, by `position: absolute` or `fixed`.
bool _positioned(_Own own) =>
    _winning(
      own,
      'position',
      (value) => switch (value.text.toLowerCase()) {
        'absolute' || 'fixed' => true,
        'static' || 'relative' || 'sticky' => false,
        _ => null,
      },
    ) ??
    false;

/// What [element] inherits from [parent], with its own declarations on top.
RunStyle _inherit(RunStyle parent, _Own own) {
  final fontSize =
      _winning(
        own,
        'font-size',
        (value) => _nonNegative(
          _length(value.text, em: parent.fontSize, percentOf: parent.fontSize),
        ),
      ) ??
      parent.fontSize;
  final lineHeight = _winning(
    own,
    'line-height',
    (value) => _lineHeight(value.text, fontSize),
  );
  return RunStyle(
    fontFamily:
        _winning(own, 'font-family', (value) => _fontFamily(value.text)) ??
        parent.fontFamily,
    fontSize: fontSize,
    fontWeight:
        _winning(own, 'font-weight', (value) => _fontWeight(value.text)) ??
        parent.fontWeight,
    italic:
        _winning(own, 'font-style', (value) => _italic(value.text)) ??
        parent.italic,
    lineHeight: lineHeight == null ? parent.lineHeight : lineHeight.px,
    color:
        _winning(own, 'color', (value) => _color(value.text)) ?? parent.color,
    letterSpacing:
        _winning(
          own,
          'letter-spacing',
          (value) => _letterSpacing(value.text, fontSize),
        ) ??
        parent.letterSpacing,
    underline:
        _winning(own, 'text-decoration', (value) => _underline(value.text)) ??
        parent.underline,
  );
}

/// Runs as HTML shows them: each stretch of white space one space, none at either end of the
/// line, and no empty run.
List<TextRun> _collapsed(List<TextRun> runs) {
  final result = <TextRun>[];
  var afterSpace = true;
  // A run left out passes its margin on: the gap stays before the text that follows.
  var margin = 0.0;
  for (final run in runs) {
    var text = run.text.replaceAll(_whiteSpace, ' ');
    if (afterSpace && text.startsWith(' ')) {
      text = text.substring(1);
    }
    margin += run.marginLeft;
    if (text.isNotEmpty) {
      afterSpace = text.endsWith(' ');
      result.add(TextRun(text, run.style, link: run.link, marginLeft: margin));
      margin = 0;
    }
  }
  if (result.isNotEmpty && result.last.text.endsWith(' ')) {
    final last = result.removeLast();
    final text = last.text.substring(0, last.text.length - 1);
    if (text.isNotEmpty) {
      result.add(
        TextRun(text, last.style, link: last.link, marginLeft: last.marginLeft),
      );
    }
  }
  return result;
}

/// One stylesheet's rules, indexed by what an element must have for them to match, and its
/// `@font-face` files.
class _StyleSheet {
  _StyleSheet._(this.rules, this.fonts) {
    for (final rule in rules) {
      final selector = rule.selector;
      if (selector.id case final id?) {
        (_byId[id] ??= []).add(rule);
      } else if (selector.classes.firstOrNull case final className?) {
        (_byClass[className] ??= []).add(rule);
      } else if (selector.tag case final tag?) {
        (_byTag[tag] ??= []).add(rule);
      } else {
        _anyElement.add(rule);
      }
    }
  }

  /// Reads the rules and font files of the stylesheet at [path]. Its rules and declarations are
  /// split here rather than by csslib, which drops the rest of a file at the first value it
  /// can't parse — a browser drops only that declaration.
  factory _StyleSheet.parse(String text, String path, BookStyles styles) {
    final rules = <_Rule>[];
    final fonts = <String, List<String>>{};
    // CSS reads an `@import` only ahead of every rule.
    var rulesBegan = false;
    for (final (prelude, body) in _blocks(_withoutComments(text))) {
      final atRule = _atRuleName.firstMatch(prelude)?[1]?.toLowerCase();
      if (atRule == 'import' && body == null) {
        if (!rulesBegan) {
          if (_importPath(prelude, path) case final imported?) {
            if (styles._sheet(imported) case final sheet?) {
              for (final rule in sheet.rules) {
                rules.add(
                  _Rule(rule.selector, rule.declarations, rules.length),
                );
              }
              for (final MapEntry(key: family, value: files)
                  in sheet.fonts.entries) {
                (fonts[family] ??= []).addAll(files);
              }
            }
          }
        }
        continue;
      }
      if (atRule != 'charset') {
        rulesBegan = true;
      }
      if (body == null) {
        continue;
      }
      if (atRule != null) {
        if (atRule == 'font-face') {
          _addFontFace(fonts, _declarations(body, path), path);
        }
        continue;
      }
      final declarations = _declarations(body, path);
      for (final selector in _selectors(prelude)) {
        rules.add(_Rule(selector, declarations, rules.length));
      }
    }
    return _StyleSheet._(rules, fonts);
  }

  /// In order, the rules it imports first.
  final List<_Rule> rules;

  final Map<String, List<String>> fonts;
  final _byId = <String, List<_Rule>>{};
  final _byClass = <String, List<_Rule>>{};
  final _byTag = <String, List<_Rule>>{};
  final _anyElement = <_Rule>[];

  /// The rules that could match an element with [tag], [id] and [classes]; each one once.
  Iterable<_Rule> candidates(String tag, String? id, Set<String> classes) => [
    ...?_byId[id],
    for (final className in classes) ...?_byClass[className],
    ...?_byTag[tag],
    ..._anyElement,
  ];
}

class _Rule {
  const _Rule(this.selector, this.declarations, this.order);

  final _Selector selector;
  final List<(String, _Value)> declarations;

  /// Its place in its stylesheet.
  final int order;
}

/// A selector of a tag, classes and an id, such as `div.cls_001` or `#page002`, and nothing
/// else: no attributes, pseudo-classes or combinators.
class _Selector {
  const _Selector(this.tag, this.id, this.classes);

  /// Null for a selector with any other part.
  static _Selector? of(css.Selector selector) {
    String? tag;
    String? id;
    final classes = <String>{};
    for (final part in selector.simpleSelectorSequences) {
      if (!part.isCombinatorNone) {
        return null;
      }
      switch (part.simpleSelector) {
        case css.ElementSelector(isWildcard: true):
          break;
        case final css.ElementSelector element:
          tag = element.name.toLowerCase();
        case final css.IdSelector selector:
          id = selector.name;
        case final css.ClassSelector selector:
          classes.add(selector.name);
        default:
          return null;
      }
    }
    return _Selector(tag, id, classes);
  }

  final String? tag;
  final String? id;
  final Set<String> classes;

  /// CSS's order of precedence: an id outweighs any number of classes, a class any number of tags.
  int get specificity =>
      (id == null ? 0 : 1 << 20) +
      (classes.length << 10) +
      (tag == null ? 0 : 1);

  bool matches(String tag, String? id, Set<String> classes) =>
      (this.tag == null || this.tag == tag) &&
      (this.id == null || this.id == id) &&
      this.classes.every(classes.contains);
}

/// The simple selectors of a rule's [prelude]; none when csslib can't read it, as a browser
/// drops a rule whose selector it can't read.
List<_Selector> _selectors(String prelude) {
  final errors = <css.Message>[];
  final tree = css.parse('$prelude{}', errors: errors);
  if (errors.isNotEmpty) {
    return const [];
  }
  return switch (tree.topLevels.singleOrNull) {
    final css.RuleSet rule => [
      for (final selector
          in rule.selectorGroup?.selectors ?? const <css.Selector>[])
        ?_Selector.of(selector),
    ],
    _ => const [],
  };
}

/// The file an `@import` brings in, from the stylesheet at [base]; null for one from outside the
/// book, or one limited to a medium other than the screen, such as `print`.
String? _importPath(String prelude, String base) {
  final match = _importPattern.firstMatch(prelude);
  if (match == null) {
    return null;
  }
  final media = match[6]!.trim().toLowerCase();
  if (media.isNotEmpty && media != 'all' && media != 'screen') {
    return null;
  }
  return _resolve(
    match[1] ?? match[2] ?? match[3] ?? match[4] ?? match[5]!,
    base,
  );
}

/// Adds the font file an `@font-face` rule's [declarations] name to [fonts], under its family.
void _addFontFace(
  Map<String, List<String>> fonts,
  List<(String, _Value)> declarations,
  String path,
) {
  String? family;
  String? file;
  for (final (property, value) in declarations) {
    switch (property) {
      case 'font-family':
        family = _fontFamily(value.text);
      case 'src':
        file = _fontFile(value.text, path);
    }
  }
  if ((family, file) case (final family?, final file?)) {
    (fonts[family] ??= []).add(file);
  }
}

/// A declaration's value as written, and the file a `url()` in it is relative to.
class _Value {
  const _Value(this.text, this.base);

  final String text;
  final String base;
}

/// An element's declarations by property, each list in the order they apply.
typedef _Own = Map<String, List<_Value>>;

/// The last of [property]'s values that [read] can make sense of — a browser drops a value it
/// can't read, and the one before it applies. Null when there is none, or when `inherit` wins.
T? _winning<T extends Object>(
  _Own own,
  String property,
  T? Function(_Value value) read,
) {
  for (final value in (own[property] ?? const <_Value>[]).reversed) {
    if (value.text.toLowerCase() == 'inherit') {
      return null;
    }
    if (read(value) case final result?) {
      return result;
    }
  }
  return null;
}

/// A rule's body as `(property, value)`, each value as written: split at each `;` outside
/// strings and brackets — a `url(data:…)` holds `;` of its own.
List<(String, _Value)> _declarations(String body, String base) {
  final declarations = <(String, _Value)>[];
  void add(String declaration) {
    final colon = declaration.indexOf(':');
    if (colon < 0) {
      return;
    }
    final property = declaration.substring(0, colon).trim().toLowerCase();
    final value = declaration
        .substring(colon + 1)
        .replaceFirst(_important, '')
        .trim();
    if (property.isNotEmpty && value.isNotEmpty) {
      declarations.add((property, _Value(value, base)));
    }
  }

  var depth = 0;
  var start = 0;
  var index = 0;
  while (index < body.length) {
    switch (body[index]) {
      case '"' || "'":
        index = _afterString(body, index);
        continue;
      case r'\':
        index += 2;
        continue;
      case '(' || '[' || '{':
        depth++;
      case ')' || ']' || '}':
        depth = math.max(0, depth - 1);
      case ';' when depth == 0:
        add(body.substring(start, index));
        start = index + 1;
    }
    index++;
  }
  if (start < body.length) {
    add(body.substring(start));
  }
  return declarations;
}

List<(String, _Value)> _inlineDeclarations(String style, String base) =>
    _declarations(_withoutComments(style), base);

/// A stylesheet's top-level rules as `(prelude, body)`: a rule's selectors, or an at-rule's name
/// and terms, and what its braces hold — null for an at-rule a `;` ends. A block left open runs
/// to the end of the text, as CSS reads it.
Iterable<(String, String?)> _blocks(String text) sync* {
  var start = 0;
  var index = 0;
  while (index < text.length) {
    // HTML's comment marks, which an old stylesheet wraps itself in, count for nothing between
    // rules.
    if (text.startsWith('<!--', index) || text.startsWith('-->', index)) {
      if (text.substring(start, index).trim().isEmpty) {
        index += text[index] == '<' ? 4 : 3;
        start = index;
        continue;
      }
    }
    switch (text[index]) {
      case '"' || "'":
        index = _afterString(text, index);
        continue;
      case r'\':
        index += 2;
        continue;
      case '{':
        final end = _closingBrace(text, index);
        yield (
          text.substring(start, index).trim(),
          text.substring(index + 1, math.min(end, text.length)),
        );
        index = end + 1;
        start = index;
        continue;
      case ';' when text.substring(start, index).trimLeft().startsWith('@'):
        yield (text.substring(start, index).trim(), null);
        start = index + 1;
      case '}':
        start = index + 1;
    }
    index++;
  }
}

/// Where the `}` that closes the `{` at [open] is; the end of [text] when none does.
int _closingBrace(String text, int open) {
  var depth = 0;
  var index = open;
  while (index < text.length) {
    switch (text[index]) {
      case '"' || "'":
        index = _afterString(text, index);
        continue;
      case r'\':
        index += 2;
        continue;
      case '{':
        depth++;
      case '}':
        depth--;
        if (depth == 0) {
          return index;
        }
    }
    index++;
  }
  return text.length;
}

/// Where the string that opens at [open] ends: after its closing quote, or at the line break or
/// the end of [text] that cuts it short.
int _afterString(String text, int open) {
  final quote = text[open];
  var index = open + 1;
  while (index < text.length) {
    final char = text[index];
    if (char == r'\') {
      index += 2;
    } else if (char == quote) {
      return index + 1;
    } else if (char == '\n') {
      return index;
    } else {
      index++;
    }
  }
  return text.length;
}

/// [text] with each comment a space, as CSS reads it.
String _withoutComments(String text) {
  if (!text.contains('/*')) {
    return text;
  }
  final result = StringBuffer();
  var start = 0;
  var index = 0;
  while (index < text.length) {
    switch (text[index]) {
      case '"' || "'":
        index = _afterString(text, index);
        continue;
      case r'\':
        index += 2;
        continue;
      case '/' when text.startsWith('/*', index):
        final end = text.indexOf('*/', index + 2);
        result
          ..write(text.substring(start, index))
          ..write(' ');
        index = end < 0 ? text.length : end + 2;
        start = index;
        continue;
    }
    index++;
  }
  result.write(text.substring(math.min(start, text.length)));
  return result.toString();
}

/// A length in CSS pixels: `px`, `em` of [em], `%` of [percentOf]; null for any other unit.
double? _length(String text, {required double em, double? percentOf}) {
  final match = _lengthPattern.firstMatch(text.trim());
  if (match == null) {
    return null;
  }
  final value = double.parse(match[1]!);
  return switch (match[2]?.toLowerCase()) {
    'px' => value,
    'em' => value * em,
    '%' => percentOf == null ? null : value * percentOf / 100,
    // CSS lets a zero go without a unit.
    _ => value == 0 ? 0 : null,
  };
}

double? _nonNegative(double? value) =>
    value != null && value >= 0 ? value : null;

double? _positive(double? value) => value != null && value > 0 ? value : null;

/// A `line-height` in CSS pixels, worked out against [fontSize] where it's declared; a null
/// [px] for `normal`, which leaves it to the font.
({double? px})? _lineHeight(String text, double fontSize) =>
    text.toLowerCase() == 'normal'
    ? (px: null)
    : switch (_nonNegative(_length(text, em: fontSize, percentOf: fontSize))) {
        final px? => (px: px),
        null => null,
      };

double? _letterSpacing(String text, double fontSize) =>
    text.toLowerCase() == 'normal' ? 0 : _length(text, em: fontSize);

/// The first family in the list, without its quotes.
String? _fontFamily(String text) {
  final match = _firstFamily.firstMatch(text);
  final family = (match?[1] ?? match?[2] ?? match?[3])?.trim();
  return family == null || family.isEmpty ? null : family;
}

FontWeight? _fontWeight(String text) => switch (text.toLowerCase()) {
  'normal' => FontWeight.w400,
  'bold' => FontWeight.w700,
  final value => switch (int.tryParse(value)) {
    final weight? when weight >= 1 && weight <= 1000 => FontWeight(weight),
    _ => null,
  },
};

bool? _italic(String text) => switch (text.toLowerCase()) {
  'normal' => false,
  'italic' => true,
  final value when value.startsWith('oblique') => true,
  _ => null,
};

bool _underline(String text) =>
    _words(text.toLowerCase()).contains('underline');

/// `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, `rgb()` or `rgba()` with an alpha or without, a
/// colour's name, or `transparent`.
Color? _color(String text) {
  final value = text.toLowerCase();
  if (value == 'transparent') {
    return const Color(0x00000000);
  }
  if (_namedColors[value] case final rgb?) {
    return Color(0xFF000000 | rgb);
  }
  if (_hexColor.firstMatch(value) case final match?) {
    final digits = match[1]!;
    final hex = digits.length <= 4
        ? [for (final digit in digits.split('')) '$digit$digit'].join()
        : digits;
    final number = int.parse(hex, radix: 16);
    // CSS writes the alpha last, Flutter first.
    return hex.length == 8
        ? Color((number & 0xFF) << 24 | number >> 8)
        : Color(0xFF000000 | number);
  }
  if (_rgbColor.firstMatch(value) case final match?) {
    final [red, green, blue] = [
      for (final group in [1, 2, 3]) math.min(255, int.parse(match[group]!)),
    ];
    final alpha = match[4] == null ? 1.0 : _alpha(match[4]!);
    return alpha == null
        ? null
        : Color.fromARGB((alpha * 255).round(), red, green, blue);
  }
  return null;
}

/// An alpha written as a number or a percentage, held to 0–1.
double? _alpha(String text) {
  final percent = text.endsWith('%');
  final number = double.tryParse(
    percent ? text.substring(0, text.length - 1) : text,
  );
  return number == null
      ? null
      : (percent ? number / 100 : number).clamp(0, 1).toDouble();
}

/// A `transform`: `matrix()`, `scale()` and `rotate()`, one after the other as CSS lists them;
/// `none` is no change. Null when it holds anything else, which drops the whole declaration.
LineTransform? _transform(String text) {
  if (text.toLowerCase() == 'none') {
    return LineTransform.identity;
  }
  var transform = LineTransform.identity;
  var end = 0;
  for (final match in _transformFunction.allMatches(text)) {
    if (text.substring(end, match.start).trim().isNotEmpty) {
      return null;
    }
    end = match.end;
    final arguments = match[2]!.trim().split(_argumentSeparator);
    final step = _transformStep(match[1]!.toLowerCase(), arguments);
    if (step == null) {
      return null;
    }
    transform = transform * step;
  }
  return end == 0 || text.substring(end).trim().isNotEmpty ? null : transform;
}

LineTransform? _transformStep(String name, List<String> arguments) {
  if (name == 'rotate') {
    return switch (arguments) {
      [final angle] => switch (_angle(angle)) {
        final radians? => LineTransform.rotation(radians),
        null => null,
      },
      _ => null,
    };
  }
  final numbers = [for (final argument in arguments) _plainNumber(argument)];
  return switch ((name, numbers)) {
    ('matrix', [final a?, final b?, final c?, final d?, final e?, final f?]) =>
      LineTransform(a, b, c, d, e, f),
    ('scale', [final both?]) => LineTransform(both, 0, 0, both, 0, 0),
    ('scale', [final x?, final y?]) => LineTransform(x, 0, 0, y, 0, 0),
    _ => null,
  };
}

/// An angle in `deg`, `rad` or `turn`, as radians clockwise; CSS lets a zero go without a unit.
double? _angle(String text) {
  final match = _anglePattern.firstMatch(text);
  if (match == null) {
    return null;
  }
  final value = double.parse(match[1]!);
  return switch (match[2]?.toLowerCase()) {
    'deg' => value * math.pi / 180,
    'rad' => value,
    'turn' => value * 2 * math.pi,
    _ => value == 0 ? 0 : null,
  };
}

double? _plainNumber(String text) =>
    _plainNumberPattern.hasMatch(text) ? double.parse(text) : null;

/// An `<img>`'s `width` or `height` attribute in CSS pixels: the number it starts with, as a
/// browser reads `1314` and `1314px` alike.
double? _attributeLength(String? text) =>
    switch (_leadingNumber.firstMatch(text ?? '')) {
      final match? => _positive(double.parse(match[1]!)),
      null => null,
    };

/// A `transform-origin` of keywords, percentages and lengths; a third value, the depth, has no
/// part in a flat page.
LineOrigin? _origin(String text, double em) {
  var words = _words(text.toLowerCase());
  if (words.length == 3) {
    words = words.sublist(0, 2);
  }
  if (words.length == 1) {
    words = words.single == 'top' || words.single == 'bottom'
        ? ['center', words.single]
        : [words.single, 'center'];
  }
  if (words case [final first, final second]) {
    final (x, y) =
        first == 'top' ||
            first == 'bottom' ||
            second == 'left' ||
            second == 'right'
        ? (second, first)
        : (first, second);
    if ((
          _originAxis(x, 'left', 'right', em),
          _originAxis(y, 'top', 'bottom', em),
        )
        case ((final alignX, final dx)?, (final alignY, final dy)?)) {
      return LineOrigin(Alignment(alignX, alignY), Offset(dx, dy));
    }
  }
  return null;
}

/// One axis of a `transform-origin`: a keyword or percentage as an alignment, a length as a
/// distance from the box's [start] edge.
(double, double)? _originAxis(
  String word,
  String start,
  String end,
  double em,
) {
  if (_axis(word, start, end) case final alignment?) {
    return (alignment, 0);
  }
  if (_length(word, em: em) case final length?) {
    return (-1, length);
  }
  return null;
}

/// A `background-image`: a picture in the book, or a null [path] for `none` and for any
/// picture from elsewhere, which a book never makes the app load.
({String? path})? _image(_Value value) {
  if (value.text.toLowerCase() == 'none') {
    return (path: null);
  }
  final match = _url.firstMatch(value.text);
  if (match == null) {
    return null;
  }
  return (path: _resolve(match[1] ?? match[2] ?? match[3]!, value.base));
}

BoxFit? _fit(String text) => switch (_words(text.toLowerCase())) {
  ['cover'] => BoxFit.cover,
  ['contain'] => BoxFit.contain,
  ['auto'] || ['auto', 'auto'] => BoxFit.none,
  ['auto', '100%'] => BoxFit.fitHeight,
  ['100%'] || ['100%', 'auto'] => BoxFit.fitWidth,
  ['100%', '100%'] => BoxFit.fill,
  _ => null,
};

/// A `background-position` of keywords or percentages. A CSS percentage lines up the same
/// point of the picture and the page, which is what an [Alignment] does.
Alignment? _alignment(String text) {
  var words = _words(text.toLowerCase());
  if (words.length == 1) {
    words = words.single == 'top' || words.single == 'bottom'
        ? ['center', words.single]
        : [words.single, 'center'];
  }
  if (words case [final first, final second]) {
    final (x, y) =
        first == 'top' ||
            first == 'bottom' ||
            second == 'left' ||
            second == 'right'
        ? (second, first)
        : (first, second);
    if ((_axis(x, 'left', 'right'), _axis(y, 'top', 'bottom')) case (
      final dx?,
      final dy?,
    )) {
      return Alignment(dx, dy);
    }
  }
  return null;
}

double? _axis(String word, String start, String end) {
  if (word == start) {
    return -1;
  }
  if (word == end) {
    return 1;
  }
  if (word == 'center') {
    return 0;
  }
  final match = _percentage.firstMatch(word);
  return match == null ? null : double.parse(match[1]!) / 50 - 1;
}

/// The first `url()` in a `src` that Flutter can load: a TrueType or OpenType file.
String? _fontFile(String text, String base) {
  for (final match in _url.allMatches(text)) {
    final reference = match[1] ?? match[2] ?? match[3]!;
    final path = reference.toLowerCase().split('?').first;
    if (path.endsWith('.ttf') || path.endsWith('.otf')) {
      return _resolve(reference, base);
    }
  }
  return null;
}

/// [reference]'s path in the archive, resolved against the file [base]; null for an address
/// outside the book, such as `http:` or `data:`.
String? _resolve(String reference, String base) {
  final uri = Uri.tryParse(reference);
  if (uri == null || uri.hasScheme || uri.hasAuthority) {
    return null;
  }
  return Uri.decodeComponent(Uri(path: base).resolveUri(uri).path);
}

double? _viewportValue(String content, String name) {
  final match = RegExp(
    '(?:^|[,;\\s])$name\\s*=\\s*($_number)',
    caseSensitive: false,
  ).firstMatch(content);
  return _positive(match == null ? null : double.tryParse(match[1]!));
}

XmlElement? _child(XmlElement parent, String localName) => parent.childElements
    .where((element) => element.localName == localName)
    .firstOrNull;

List<String> _words(String text) => [
  for (final word in text.trim().split(_whiteSpace))
    if (word.isNotEmpty) word,
];

const _number = r'[+-]?(?:\d+\.?\d*|\.\d+)';
final _lengthPattern = RegExp('^($_number)(px|em|%)?\$', caseSensitive: false);
final _percentage = RegExp('^($_number)%\$');
final _hexColor = RegExp(r'^#([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$');
final _rgbColor = RegExp(
  r'^rgba?\(\s*(\d{1,3})(?:\s*,\s*|\s+)(\d{1,3})(?:\s*,\s*|\s+)(\d{1,3})'
  '(?:\\s*[,/]\\s*($_number%?))?'
  r'\s*\)$',
);
final _transformFunction = RegExp(r'([a-zA-Z]+)\(([^)]*)\)');
final _argumentSeparator = RegExp(r'\s*,\s*|\s+');
final _plainNumberPattern = RegExp('^$_number\$');
final _leadingNumber = RegExp(r'^\s*(\d+(?:\.\d+)?)');
final _anglePattern = RegExp(
  '^($_number)(deg|rad|turn)?\$',
  caseSensitive: false,
);
final _url = RegExp(
  r'''url\(\s*(?:"([^"]*)"|'([^']*)'|([^)\s]*))\s*\)''',
  caseSensitive: false,
);
final _firstFamily = RegExp(r'''^\s*(?:"([^"]*)"|'([^']*)'|([^,]+))''');
final _important = RegExp(r'\s*!\s*important\s*$', caseSensitive: false);
final _atRuleName = RegExp(r'^@([-\w]+)');
final _importPattern = RegExp(
  r'''^@import\s*(?:url\(\s*(?:"([^"]*)"|'([^']*)'|([^)\s]*))\s*\)|"([^"]*)"|'([^']*)')(.*)$''',
  caseSensitive: false,
  dotAll: true,
);
// HTML's white space; a no-break space is text.
final _whiteSpace = RegExp(r'[ \t\n\r\f]+');

/// CSS's named colours as CSS Color 4 lists them, each as its red, green and blue.
const _namedColors = {
  'aliceblue': 0xF0F8FF,
  'antiquewhite': 0xFAEBD7,
  'aqua': 0x00FFFF,
  'aquamarine': 0x7FFFD4,
  'azure': 0xF0FFFF,
  'beige': 0xF5F5DC,
  'bisque': 0xFFE4C4,
  'black': 0x000000,
  'blanchedalmond': 0xFFEBCD,
  'blue': 0x0000FF,
  'blueviolet': 0x8A2BE2,
  'brown': 0xA52A2A,
  'burlywood': 0xDEB887,
  'cadetblue': 0x5F9EA0,
  'chartreuse': 0x7FFF00,
  'chocolate': 0xD2691E,
  'coral': 0xFF7F50,
  'cornflowerblue': 0x6495ED,
  'cornsilk': 0xFFF8DC,
  'crimson': 0xDC143C,
  'cyan': 0x00FFFF,
  'darkblue': 0x00008B,
  'darkcyan': 0x008B8B,
  'darkgoldenrod': 0xB8860B,
  'darkgray': 0xA9A9A9,
  'darkgreen': 0x006400,
  'darkgrey': 0xA9A9A9,
  'darkkhaki': 0xBDB76B,
  'darkmagenta': 0x8B008B,
  'darkolivegreen': 0x556B2F,
  'darkorange': 0xFF8C00,
  'darkorchid': 0x9932CC,
  'darkred': 0x8B0000,
  'darksalmon': 0xE9967A,
  'darkseagreen': 0x8FBC8F,
  'darkslateblue': 0x483D8B,
  'darkslategray': 0x2F4F4F,
  'darkslategrey': 0x2F4F4F,
  'darkturquoise': 0x00CED1,
  'darkviolet': 0x9400D3,
  'deeppink': 0xFF1493,
  'deepskyblue': 0x00BFFF,
  'dimgray': 0x696969,
  'dimgrey': 0x696969,
  'dodgerblue': 0x1E90FF,
  'firebrick': 0xB22222,
  'floralwhite': 0xFFFAF0,
  'forestgreen': 0x228B22,
  'fuchsia': 0xFF00FF,
  'gainsboro': 0xDCDCDC,
  'ghostwhite': 0xF8F8FF,
  'gold': 0xFFD700,
  'goldenrod': 0xDAA520,
  'gray': 0x808080,
  'green': 0x008000,
  'greenyellow': 0xADFF2F,
  'grey': 0x808080,
  'honeydew': 0xF0FFF0,
  'hotpink': 0xFF69B4,
  'indianred': 0xCD5C5C,
  'indigo': 0x4B0082,
  'ivory': 0xFFFFF0,
  'khaki': 0xF0E68C,
  'lavender': 0xE6E6FA,
  'lavenderblush': 0xFFF0F5,
  'lawngreen': 0x7CFC00,
  'lemonchiffon': 0xFFFACD,
  'lightblue': 0xADD8E6,
  'lightcoral': 0xF08080,
  'lightcyan': 0xE0FFFF,
  'lightgoldenrodyellow': 0xFAFAD2,
  'lightgray': 0xD3D3D3,
  'lightgreen': 0x90EE90,
  'lightgrey': 0xD3D3D3,
  'lightpink': 0xFFB6C1,
  'lightsalmon': 0xFFA07A,
  'lightseagreen': 0x20B2AA,
  'lightskyblue': 0x87CEFA,
  'lightslategray': 0x778899,
  'lightslategrey': 0x778899,
  'lightsteelblue': 0xB0C4DE,
  'lightyellow': 0xFFFFE0,
  'lime': 0x00FF00,
  'limegreen': 0x32CD32,
  'linen': 0xFAF0E6,
  'magenta': 0xFF00FF,
  'maroon': 0x800000,
  'mediumaquamarine': 0x66CDAA,
  'mediumblue': 0x0000CD,
  'mediumorchid': 0xBA55D3,
  'mediumpurple': 0x9370DB,
  'mediumseagreen': 0x3CB371,
  'mediumslateblue': 0x7B68EE,
  'mediumspringgreen': 0x00FA9A,
  'mediumturquoise': 0x48D1CC,
  'mediumvioletred': 0xC71585,
  'midnightblue': 0x191970,
  'mintcream': 0xF5FFFA,
  'mistyrose': 0xFFE4E1,
  'moccasin': 0xFFE4B5,
  'navajowhite': 0xFFDEAD,
  'navy': 0x000080,
  'oldlace': 0xFDF5E6,
  'olive': 0x808000,
  'olivedrab': 0x6B8E23,
  'orange': 0xFFA500,
  'orangered': 0xFF4500,
  'orchid': 0xDA70D6,
  'palegoldenrod': 0xEEE8AA,
  'palegreen': 0x98FB98,
  'paleturquoise': 0xAFEEEE,
  'palevioletred': 0xDB7093,
  'papayawhip': 0xFFEFD5,
  'peachpuff': 0xFFDAB9,
  'peru': 0xCD853F,
  'pink': 0xFFC0CB,
  'plum': 0xDDA0DD,
  'powderblue': 0xB0E0E6,
  'purple': 0x800080,
  'rebeccapurple': 0x663399,
  'red': 0xFF0000,
  'rosybrown': 0xBC8F8F,
  'royalblue': 0x4169E1,
  'saddlebrown': 0x8B4513,
  'salmon': 0xFA8072,
  'sandybrown': 0xF4A460,
  'seagreen': 0x2E8B57,
  'seashell': 0xFFF5EE,
  'sienna': 0xA0522D,
  'silver': 0xC0C0C0,
  'skyblue': 0x87CEEB,
  'slateblue': 0x6A5ACD,
  'slategray': 0x708090,
  'slategrey': 0x708090,
  'snow': 0xFFFAFA,
  'springgreen': 0x00FF7F,
  'steelblue': 0x4682B4,
  'tan': 0xD2B48C,
  'teal': 0x008080,
  'thistle': 0xD8BFD8,
  'tomato': 0xFF6347,
  'turquoise': 0x40E0D0,
  'violet': 0xEE82EE,
  'wheat': 0xF5DEB3,
  'white': 0xFFFFFF,
  'whitesmoke': 0xF5F5F5,
  'yellow': 0xFFFF00,
  'yellowgreen': 0x9ACD32,
};
