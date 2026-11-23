import 'dart:async';

import 'package:bookserver/data/epub_book.dart';
import 'package:bookserver/data/epub_layout.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/epub_image.dart';
import 'package:bookserver/ui/notice.dart';
import 'package:bookserver/ui/readers/page_turner.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Loads the [files] of one font family under the name [family].
typedef FontLoad = Future<void> Function(String family, List<Uint8List> files);

/// A fixed-layout book's pages, each parsed the first time it's needed, and the fonts they use.
class FixedLayoutBook {
  FixedLayoutBook(this.book, this.id, {FontLoad? loadFont})
    : _styles = BookStyles(book),
      _loadFont = loadFont ?? _loadWithFontLoader;

  final EpubBook book;

  /// The book's id on the server, which keeps its fonts apart from another book's.
  final int id;

  final BookStyles _styles;
  final FontLoad _loadFont;

  /// Pages parsed so far; null for one that isn't well-formed or gives no size.
  final _pages = <int, FixedPage?>{};
  final _prepared = <int>{};

  /// The font families loaded in this run of the app, by name: Flutter can't unload a font, so
  /// each is loaded once.
  static final _fonts = <String, Future<void>>{};

  /// Page [index], parsed if it hasn't been, with its fonts loaded; null for a page that isn't
  /// well-formed or gives no size.
  Future<FixedPage?> prepare(int index) async {
    final page = _pages.putIfAbsent(index, () {
      try {
        return FixedPage.parse(_styles, index);
      } on FormatException {
        return null;
      }
    });
    if (page != null) {
      await Future.wait([
        for (final MapEntry(key: family, value: files) in page.fonts.entries)
          _fonts[fontFamily(family)] ??= _load(fontFamily(family), files),
      ]);
      _prepared.add(index);
    }
    return page;
  }

  /// Page [index] when [prepare] has finished with it.
  FixedPage? prepared(int index) =>
      _prepared.contains(index) ? _pages[index] : null;

  /// Whether page [index] was parsed and can't be read.
  bool failed(int index) => _pages.containsKey(index) && _pages[index] == null;

  /// The name the book's font [family] is loaded under.
  String fontFamily(String family) => 'book$id-$family';

  Future<void> _load(String name, List<String> files) async {
    try {
      await _loadFont(name, [for (final path in files) ?book.read(path)]);
    } on Exception {
      // A font that can't be loaded leaves its text in the default font.
    }
  }
}

Future<void> _loadWithFontLoader(String family, List<Uint8List> files) {
  final loader = FontLoader(family);
  for (final bytes in files) {
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  return loader.load();
}

/// A page of a fixed-layout book, drawn at the size the book gives it and scaled to fit: its
/// background, then every line where the book places it. A tap on a link turns to its page.
class FixedLayoutPage extends StatefulWidget {
  const FixedLayoutPage({
    super.key,
    required this.book,
    required this.index,
    required this.decodeWidth,
  });

  final FixedLayoutBook book;
  final int index;

  /// The widest, in pixels, the page's picture is decoded.
  final int decodeWidth;

  @override
  State<FixedLayoutPage> createState() => _FixedLayoutPageState();
}

class _FixedLayoutPageState extends State<FixedLayoutPage> {
  FixedPage? _page;
  var _failed = false;
  final _links = Map<TextRun, TapGestureRecognizer>.identity();
  ValueListenable<bool>? _moving;

  @override
  void initState() {
    super.initState();
    if (widget.book.prepared(widget.index) case final page?) {
      _show(page);
    } else if (widget.book.failed(widget.index)) {
      _failed = true;
    } else {
      // Parsed once the pages hold still: a page takes some milliseconds, which during a turn
      // would drop frames.
      _moving = PageTurner.of(context).moving..addListener(_prepareWhenStill);
      _prepareWhenStill();
    }
  }

  @override
  void dispose() {
    _moving?.removeListener(_prepareWhenStill);
    for (final link in _links.values) {
      link.dispose();
    }
    super.dispose();
  }

  void _prepareWhenStill() {
    final moving = _moving;
    if (moving == null || moving.value) {
      return;
    }
    moving.removeListener(_prepareWhenStill);
    _moving = null;
    // After this frame: the turner says it holds still in the middle of one, while nothing may be
    // rebuilt.
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => unawaited(_prepare()))
      ..ensureVisualUpdate();
  }

  Future<void> _prepare() async {
    final page = await widget.book.prepare(widget.index);
    if (!mounted) {
      return;
    }
    setState(() {
      if (page == null) {
        _failed = true;
      } else {
        _show(page);
      }
    });
  }

  void _show(FixedPage page) {
    _page = page;
    for (final line in page.lines) {
      for (final run in line.runs) {
        if (run.link case final target?) {
          _links[run] = TapGestureRecognizer()
            ..onTap = () => PageTurner.of(context).turnTo(target);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Notice(
        text: context.t('reader.page_failed'),
        color: Theme.of(context).colorScheme.error,
      );
    }
    final page = _page;
    if (page == null) {
      return const SizedBox.expand();
    }
    final background = page.background;
    return FittedBox(
      child: SizedBox.fromSize(
        size: page.size,
        child: ClipRect(
          // The book's styles alone, none of the app's text theme.
          child: DefaultTextStyle(
            style: const TextStyle(),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(color: background.color ?? _paper),
                ),
                if (background.image case final path?)
                  Positioned.fill(
                    child: Image(
                      image: ResizeImage(
                        EpubImage(widget.book.book, path),
                        width: widget.decodeWidth,
                        allowUpscaling: false,
                      ),
                      fit: background.fit,
                      alignment: background.alignment,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox(),
                    ),
                  ),
                for (final line in page.lines)
                  Positioned(
                    left: line.position.dx,
                    top: line.placedByBottom ? null : line.position.dy,
                    bottom: line.placedByBottom
                        ? page.size.height - line.position.dy
                        : null,
                    child: Transform(
                      transform: _matrix(line.transform),
                      alignment: line.origin.alignment,
                      origin: line.origin.offset,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            for (final run in line.runs)
                              TextSpan(
                                text: run.text,
                                style: _textStyle(run.style, page),
                                recognizer: _links[run],
                              ),
                          ],
                        ),
                        strutStyle: _strutStyle(line.style, page),
                        softWrap: false,
                        textScaler: TextScaler.noScaling,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _textStyle(RunStyle style, FixedPage page) => TextStyle(
    fontFamily: _family(style.fontFamily, page),
    fontSize: style.fontSize,
    fontWeight: style.fontWeight,
    fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
    height: _height(style),
    // CSS puts half a line's spare height above its text and half below.
    leadingDistribution: TextLeadingDistribution.even,
    color: style.color,
    letterSpacing: style.letterSpacing,
    decoration: style.underline
        ? TextDecoration.underline
        : TextDecoration.none,
  );

  StrutStyle _strutStyle(RunStyle style, FixedPage page) => StrutStyle(
    fontFamily: _family(style.fontFamily, page),
    fontSize: style.fontSize,
    fontWeight: style.fontWeight,
    fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
    height: _height(style),
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// The name a family is loaded under when the book brings its files; the name as written
  /// otherwise.
  String? _family(String? family, FixedPage page) =>
      family != null && page.fonts.containsKey(family)
      ? widget.book.fontFamily(family)
      : family;

  double? _height(RunStyle style) => switch (style.lineHeight) {
    final lineHeight? when style.fontSize > 0 => lineHeight / style.fontSize,
    _ => null,
  };
}

// A page that gives no colour of its own is white, as a browser shows it: its text was set on
// paper, not on the app's theme.
const _paper = Color(0xFFFFFFFF);

/// [transform] as the 4×4 matrix Flutter draws with.
Matrix4 _matrix(LineTransform transform) => Matrix4.identity()
  ..setEntry(0, 0, transform.a)
  ..setEntry(1, 0, transform.b)
  ..setEntry(0, 1, transform.c)
  ..setEntry(1, 1, transform.d)
  ..setEntry(0, 3, transform.e)
  ..setEntry(1, 3, transform.f);
