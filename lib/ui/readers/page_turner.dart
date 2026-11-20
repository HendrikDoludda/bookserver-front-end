import 'package:bookserver/ui/readers/tap_zones.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Shows [count] pages one at a time, zoomable, turned by a swipe, the arrow keys or a tap on
/// either edge. Right to left with [rightToLeft]: then page 1 is at the right, and a swipe to the
/// right, the left arrow and the left edge go forward.
///
/// [pageBuilder] builds page `index`; a picture on it is decoded at most `decodeWidth` pixels
/// wide.
class PageTurner extends StatefulWidget {
  const PageTurner({
    super.key,
    required this.count,
    required this.pageBuilder,
    this.rightToLeft = false,
    this.onPageChanged,
    this.onTap,
  }) : assert(count > 0);

  final int count;
  final Widget Function(BuildContext context, int index, int decodeWidth)
  pageBuilder;

  /// Whether the pages run right to left, as a manga's do.
  final bool rightToLeft;

  /// Called with the index of the page a turn lands on.
  final ValueChanged<int>? onPageChanged;

  /// Called for a tap in the middle of a page that nothing on it took, such as a link.
  final VoidCallback? onTap;

  /// The page turner that shows [context], to turn its pages from inside one.
  static PageTurnerState of(BuildContext context) =>
      context.findAncestorStateOfType<PageTurnerState>()!;

  @override
  State<PageTurner> createState() => PageTurnerState();
}

class PageTurnerState extends State<PageTurner> {
  final _pages = PageController();
  final _moving = ValueNotifier(false);

  /// Whether the pages are moving: a swipe, a turn, a link's jump.
  ValueListenable<bool> get moving => _moving;

  // One zoom for every page: turning the page resets it, and while a page is zoomed no swipe
  // reaches the pages beside it.
  final _zoom = TransformationController();

  var _index = 0;
  var _zoomed = false;

  // Sharp up to a 2× zoom, where a full-size scan would decode to about 100 MB. Fixed while the
  // book is open, so resizing the window or turning the phone doesn't fetch every page again.
  late final int _decodeWidth =
      (MediaQuery.sizeOf(context).shortestSide *
              MediaQuery.devicePixelRatioOf(context) *
              2)
          .round();

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_zoomChanged);
  }

  @override
  void dispose() {
    _pages.dispose();
    _moving.dispose();
    _zoom.dispose();
    super.dispose();
  }

  bool _scrolled(ScrollNotification notification) {
    if (notification.depth == 0) {
      if (notification is ScrollStartNotification) {
        _moving.value = true;
      } else if (notification is ScrollEndNotification) {
        _moving.value = false;
      }
    }
    return false;
  }

  void _zoomChanged() {
    // A pinch back to full size can leave the scale a rounding error above 1.
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) {
      setState(() => _zoomed = zoomed);
    }
  }

  /// Goes straight to page [index], at normal size, as a link does.
  void turnTo(int index) {
    if (index < 0 || index >= widget.count) {
      return;
    }
    _zoom.value = Matrix4.identity();
    _pages.jumpToPage(index);
  }

  void _turn(int by) {
    final target = _index + by;
    if (target < 0 || target >= widget.count) {
      return;
    }
    _zoom.value = Matrix4.identity();
    _pages.animateToPage(
      target,
      duration: Durations.medium2,
      curve: Easing.standard,
    );
  }

  void _pageChanged(int index) {
    setState(() => _index = index);
    widget.onPageChanged?.call(index);
  }

  void _tapped(TapUpDetails details) {
    final width = context.size?.width;
    if (width == null) {
      return;
    }
    final dx = details.localPosition.dx;
    switch (tapZoneAt(dx, width, rightToLeft: widget.rightToLeft)) {
      case TapZone.previous:
        _turn(-1);
      case TapZone.next:
        _turn(1);
      case TapZone.middle:
        widget.onTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    // The turn that goes to the right on screen.
    final rightward = widget.rightToLeft ? -1 : 1;
    return GestureDetector(
      onTapUp: _tapped,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _turn(-rightward),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _turn(rightward),
        },
        child: Focus(
          autofocus: true,
          child: NotificationListener<ScrollNotification>(
            onNotification: _scrolled,
            child: PageView.builder(
              controller: _pages,
              // A PageView also runs right to left in a language written that way; the pages
              // follow the reading mode alone.
              reverse:
                  widget.rightToLeft !=
                  (Directionality.of(context) == TextDirection.rtl),
              // Builds the page on either side as well, so the next one is loaded before it's
              // turned to.
              allowImplicitScrolling: true,
              physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
              itemCount: widget.count,
              onPageChanged: _pageChanged,
              itemBuilder: (context, index) => InteractiveViewer(
                transformationController: _zoom,
                minScale: 1,
                child: widget.pageBuilder(context, index, _decodeWidth),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
