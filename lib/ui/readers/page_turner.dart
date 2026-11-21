import 'package:bookserver/ui/readers/tap_zones.dart';
import 'package:bookserver/ui/readers/zoom.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// The widest, in pixels, a reader decodes a page's pictures: twice the window's shorter side.
/// Taken once while a book is open, so resizing the window or turning the phone fetches no page
/// again; the shorter side doesn't change when the phone turns.
// Sharp up to a 2× zoom, where a full-size scan would decode to about 100 MB.
int pageDecodeWidth(BuildContext context) =>
    (MediaQuery.sizeOf(context).shortestSide *
            MediaQuery.devicePixelRatioOf(context) *
            2)
        .round();

/// Shows [count] pages one at a time, turned by a swipe, the arrow keys or a tap on either edge.
/// Right to left with [rightToLeft]: then page 1 is at the right, and a swipe to the right, the
/// left arrow and the left edge go forward.
///
/// Every page shows at one zoom step — [initialZoom] until [PageTurnerState.zoomTo] picks another —
/// and a pinch zooms freely on top of it until the next turn.
///
/// [pageBuilder] builds page `index`; a picture on it is decoded at most `decodeWidth` pixels
/// wide.
class PageTurner extends StatefulWidget {
  const PageTurner({
    super.key,
    required this.count,
    required this.pageBuilder,
    this.initialIndex = 0,
    this.rightToLeft = false,
    this.initialZoom = ZoomStep.fitPage,
    this.pageShape,
    this.onPageChanged,
    this.onTap,
    this.onPinch,
  }) : assert(count > 0 && initialIndex >= 0 && initialIndex < count);

  final int count;
  final Widget Function(BuildContext context, int index, int decodeWidth)
  pageBuilder;

  /// The page shown first.
  final int initialIndex;

  /// Whether the pages run right to left, as a manga's do.
  final bool rightToLeft;

  /// The zoom step every page shows at first.
  final ZoomStep initialZoom;

  /// Page `index`'s width divided by its height, which fitting its width needs; where it gives
  /// none, a page is taken to have the window's shape.
  final double? Function(int index)? pageShape;

  /// Called with the index of the page a turn lands on.
  final ValueChanged<int>? onPageChanged;

  /// Called for a tap in the middle of a page that nothing on it took, such as a link.
  final VoidCallback? onTap;

  /// Called when a pinch has left the page at another scale than its zoom step's.
  final VoidCallback? onPinch;

  /// The page turner that shows [context], to turn its pages from inside one.
  static PageTurnerState of(BuildContext context) =>
      context.findAncestorStateOfType<PageTurnerState>()!;

  @override
  State<PageTurner> createState() => PageTurnerState();
}

class PageTurnerState extends State<PageTurner> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  final _moving = ValueNotifier(false);

  /// Whether the pages are moving: a swipe, a turn, a link's jump.
  ValueListenable<bool> get moving => _moving;

  // One zoom for every page: a turn sets it to the step, and while a page is zoomed no swipe
  // reaches the pages beside it.
  late final _zoom = _PageZoom(_keptOnPage);

  late var _index = widget.initialIndex;
  var _zoomed = false;
  late final int _decodeWidth = pageDecodeWidth(context);
  late var _step = widget.initialZoom;

  /// The pages' size, once they are laid out.
  Size? _size;

  /// The scale when the gesture on a page started, to tell a pinch from a drag.
  var _scaleAtStart = 1.0;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_zoomChanged);
  }

  @override
  void didUpdateWidget(PageTurner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A page wider than the window starts on the other side.
    if (widget.rightToLeft != oldWidget.rightToLeft) {
      _showStepSoon();
    }
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
        // Only once a swipe has settled: a page zoomed past its width would stop it midway.
        _showStep(_index);
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

  /// Shows every page at [step] from now on, the page on screen at once.
  void zoomTo(ZoomStep step) {
    _step = step;
    _showStep(_index);
  }

  void _showStep(int index) {
    final size = _size;
    if (size == null) {
      return;
    }
    _zoom.show(
      zoomOf(
        _step,
        widget.pageShape?.call(index) ?? size.aspectRatio,
        size,
        rightToLeft: widget.rightToLeft,
      ),
    );
  }

  /// [value] kept on the page on screen, as a gesture leaves it.
  Matrix4 _keptOnPage(Matrix4 value) {
    final size = _size;
    if (size == null) {
      return value;
    }
    final shape = widget.pageShape?.call(_index) ?? size.aspectRatio;
    return keepOnPage(value, shape, size);
  }

  /// [_showStep] after this frame, for a change the framework reports while it builds or lays out.
  void _showStepSoon() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) {
      _showStep(_index);
    }
  });

  /// Goes straight to page [index], at the zoom step, as a link does.
  void turnTo(int index) {
    if (index < 0 || index >= widget.count) {
      return;
    }
    _showStep(index);
    _pages.jumpToPage(index);
  }

  void _turn(int by) {
    final target = _index + by;
    if (target < 0 || target >= widget.count) {
      return;
    }
    // At once, so the page slides in at its step.
    _showStep(target);
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

  void _interactionEnded(ScaleEndDetails details) {
    final scale = _zoom.value.getMaxScaleOnAxis();
    if ((scale / _scaleAtStart - 1).abs() > 0.01) {
      widget.onPinch?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    // The turn that goes to the right on screen.
    final rightward = widget.rightToLeft ? -1 : 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size != _size) {
          // A step such as fit width depends on the window.
          _size = size;
          _showStepSoon();
        }
        return _pagesIn(context, rightward);
      },
    );
  }

  Widget _pagesIn(BuildContext context, int rightward) {
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
                // Room above the largest step, 300 %.
                maxScale: 4,
                onInteractionStart: (_) =>
                    _scaleAtStart = _zoom.value.getMaxScaleOnAxis(),
                onInteractionEnd: _interactionEnded,
                child: widget.pageBuilder(context, index, _decodeWidth),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The zoom the pages share, kept on the page on screen however a gesture moves it.
class _PageZoom extends TransformationController {
  _PageZoom(this._keep);

  final Matrix4 Function(Matrix4 value) _keep;

  /// Shows [value] as it is: a zoom step, which keeps its page on screen already.
  void show(Matrix4 value) => super.value = value;

  // Every pinch, drag and glide after a flick writes through here.
  @override
  set value(Matrix4 value) => super.value = _keep(value);
}
