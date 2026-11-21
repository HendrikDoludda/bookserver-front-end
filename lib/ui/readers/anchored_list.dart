import 'package:material_ui/material_ui.dart';

/// A list of [count] items that can show any item at its top, just below the reader's bar, without
/// laying out the items before it: from [initialItem] when it opens, from any other through
/// [AnchoredListState.showItem]. Only the items near the screen are built.
///
/// [guessedHeights] holds a guess at each item's height, which gives the list its length — and the
/// scrollbar its size — until the items are built.
class AnchoredList extends StatefulWidget {
  const AnchoredList({
    super.key,
    required this.count,
    required this.itemBuilder,
    required this.guessedHeights,
    this.initialItem = 0,
  }) : assert(initialItem >= 0 && (initialItem < count || count == 0));

  final int count;
  final IndexedWidgetBuilder itemBuilder;
  final List<double> guessedHeights;
  final int initialItem;

  @override
  State<AnchoredList> createState() => AnchoredListState();
}

class AnchoredListState extends State<AnchoredList> {
  // The items from the anchor on run down from the top; the ones before it lie above, built
  // upwards as they scroll into view.
  late var _anchor = widget.initialItem;

  /// Counts the times [showItem] was asked, so that showing the anchor again starts afresh.
  var _shown = 0;

  final _forward = UniqueKey();

  /// The items built, by index, with the context that built each.
  final _built = <int, BuildContext>{};

  /// Shows item [index] at the top, just below the bar.
  void showItem(int index) {
    if (index < 0 || index >= widget.count) {
      return;
    }
    setState(() {
      _anchor = index;
      _shown++;
    });
  }

  /// The item at the top, the first one reaching below the bar; null before any is laid out.
  int? get topItem {
    final list = context.findRenderObject();
    if (list is! RenderBox || !list.hasSize) {
      return null;
    }
    final line = MediaQuery.paddingOf(context).top;
    for (final index in _built.keys.toList()..sort()) {
      final box = _built[index]!.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) {
        continue;
      }
      final top = box.localToGlobal(Offset.zero, ancestor: list).dy;
      if (top + box.size.height > line) {
        return index;
      }
    }
    return null;
  }

  Widget _item(BuildContext context, int index) => _Built(
    index: index,
    built: _built,
    child: widget.itemBuilder(context, index),
  );

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final anchor = _anchor.clamp(0, widget.count == 0 ? 0 : widget.count - 1);
    // Where each item starts, guessed, and where the last one ends.
    final starts = [0.0];
    for (final height in widget.guessedHeights) {
      starts.add(starts.last + height);
    }
    double above(int index) => starts[index];
    double below(int index) => starts.last - starts[index + 1];
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        return CustomScrollView(
          // A new anchor is a new list, scrolled to its top.
          key: ValueKey((anchor, _shown)),
          center: _forward,
          // The anchor's top just below the bar, as a list's first item starts.
          anchor: height > 0 ? (padding.top / height).clamp(0.0, 1.0) : 0.0,
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: padding.top)),
            SliverList(
              delegate: _Guessed(
                (context, index) => _item(context, anchor - 1 - index),
                childCount: anchor,
                rest: (index) => above(anchor - 1 - index),
              ),
            ),
            SliverList(
              key: _forward,
              delegate: _Guessed(
                (context, index) => _item(context, anchor + index),
                childCount: widget.count - anchor,
                rest: (index) => below(anchor + index),
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: padding.bottom)),
          ],
        );
      },
    );
  }
}

/// Builds a run of items, and gives its sliver a length from their guessed heights: Flutter's own
/// guess averages the items built so far, which swings between a heading and a long paragraph.
class _Guessed extends SliverChildBuilderDelegate {
  _Guessed(super.builder, {required int super.childCount, required this.rest});

  /// For child `index`, the guessed height of the children after it.
  final double Function(int index) rest;

  @override
  double estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) => trailingScrollOffset + rest(lastIndex);
}

/// An item that notes itself in [built] while it is built, so the list can tell which is on top.
class _Built extends StatefulWidget {
  const _Built({required this.index, required this.built, required this.child});

  final int index;
  final Map<int, BuildContext> built;
  final Widget child;

  @override
  State<_Built> createState() => _BuiltState();
}

class _BuiltState extends State<_Built> {
  @override
  void initState() {
    super.initState();
    widget.built[widget.index] = context;
  }

  @override
  void didUpdateWidget(_Built oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _forget(oldWidget.index);
      widget.built[widget.index] = context;
    }
  }

  @override
  void dispose() {
    _forget(widget.index);
    super.dispose();
  }

  // Only its own note: another item may have taken the index since.
  void _forget(int index) {
    if (identical(widget.built[index], context)) {
      widget.built.remove(index);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
