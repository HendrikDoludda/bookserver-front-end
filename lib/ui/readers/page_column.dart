import 'package:bookserver/ui/readers/page_turner.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Shows a book's pages top to bottom in one scrolling column, each as wide as the column, from
/// page [initialIndex] on; scrolled by a drag, the arrow and page keys or space, with no zoom.
/// Every page is laid out at its listed size before its picture arrives, so nothing moves while
/// pages load.
///
/// [pageBuilder] builds page `index`, as [PageTurner]'s does.
class PageColumn extends StatefulWidget {
  const PageColumn({
    super.key,
    required this.sizes,
    required this.pageBuilder,
    this.initialIndex = 0,
    this.onPageChanged,
    this.onTap,
  });

  /// Each page's width and height in pixels as the page list gives them; null where it gives
  /// none.
  final List<Size?> sizes;

  final Widget Function(BuildContext context, int index, int decodeWidth)
  pageBuilder;

  /// The page whose top is at the top when the column opens.
  final int initialIndex;

  /// Called with the index of the page in the middle of the screen when another one comes there.
  final ValueChanged<int>? onPageChanged;

  /// Called for a tap that nothing on a page took.
  final VoidCallback? onTap;

  @override
  State<PageColumn> createState() => _PageColumnState();
}

/// Each page's shape, its width divided by its height: as listed, else the last shape listed
/// before it, else 2:3, a comic page's usual shape.
List<double> pageShapes(List<Size?> sizes) {
  var shape = 2 / 3;
  return [for (final size in sizes) shape = size?.aspectRatio ?? shape];
}

class _PageColumnState extends State<PageColumn> {
  /// Where each page starts in a column 1 wide, and where the last one ends; in a column w wide,
  /// each lies w times as far down.
  late final List<double> _tops = () {
    final tops = [0.0];
    for (final shape in pageShapes(widget.sizes)) {
      tops.add(tops.last + 1 / shape);
    }
    return tops;
  }();

  // The page turner's width, so switching modes reuses the pictures it decoded; twice the shorter
  // side covers the column's width either way the phone is held.
  late final int _decodeWidth = pageDecodeWidth(context);

  ScrollController? _scroll;
  double? _width;

  /// The room above the first page that the list leaves for the reader's bar.
  var _paddingTop = 0.0;

  late var _index = widget.initialIndex;

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  void _scrolled() {
    final width = _width;
    final position = _scroll!.position;
    if (width == null || width == 0 || !position.hasContentDimensions) {
      return;
    }
    final middle =
        (position.pixels + position.viewportDimension / 2 - _paddingTop) /
        width;
    final index = _tops
        .lastIndexWhere((top) => top <= middle)
        .clamp(0, widget.sizes.length - 1);
    if (index != _index) {
      _index = index;
      widget.onPageChanged?.call(index);
    }
  }

  void _scrollBy(double screens) {
    final position = _scroll!.position;
    position.animateTo(
      (position.pixels + position.viewportDimension * screens).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
      duration: Durations.medium2,
      curve: Easing.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    _paddingTop = MediaQuery.paddingOf(context).top;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final scroll = _scroll ??= ScrollController(
          initialScrollOffset: width * _tops[widget.initialIndex],
        )..addListener(_scrolled);
        final before = _width;
        if (before != null &&
            before != width &&
            scroll.hasClients &&
            scroll.position.hasPixels) {
          // Every page scales with the width, so this keeps the same spot of the same page under
          // the bar. Set during layout, before the list is laid out at the new width.
          scroll.position.correctPixels(
            scroll.position.pixels * width / before,
          );
        }
        _width = width;
        return GestureDetector(
          onTap: widget.onTap,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  _scrollBy(_step),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  _scrollBy(-_step),
              const SingleActivator(LogicalKeyboardKey.pageDown): () =>
                  _scrollBy(_screen),
              const SingleActivator(LogicalKeyboardKey.pageUp): () =>
                  _scrollBy(-_screen),
              const SingleActivator(LogicalKeyboardKey.space): () =>
                  _scrollBy(_screen),
              const SingleActivator(
                LogicalKeyboardKey.space,
                shift: true,
              ): () =>
                  _scrollBy(-_screen),
            },
            child: Focus(
              autofocus: true,
              child: ListView.custom(
                controller: scroll,
                // A screen beyond each edge, so the next page loads before it scrolls in.
                scrollCacheExtent: const ScrollCacheExtent.viewport(1),
                itemExtentBuilder: (index, _) =>
                    width * (_tops[index + 1] - _tops[index]),
                childrenDelegate: _ExactLength(
                  (context, index) =>
                      widget.pageBuilder(context, index, _decodeWidth),
                  childCount: widget.sizes.length,
                  length: width * _tops.last,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Builds the pages, and gives the list its length from their sizes: Flutter would guess it from
/// the pages built so far, and could stop the list short of the page it opens at.
class _ExactLength extends SliverChildBuilderDelegate {
  _ExactLength(
    super.builder, {
    required int super.childCount,
    required this.length,
  });

  final double length;

  @override
  double estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) => length;
}

// An arrow key moves a tenth of the screen; a page key or space a screen less a strip, which
// stays in sight to keep the place.
const _step = 0.1;
const _screen = 0.9;
