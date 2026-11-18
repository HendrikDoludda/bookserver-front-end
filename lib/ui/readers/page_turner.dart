import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Shows [count] pages one at a time, swiped or turned with the arrow keys, zoomable, with
/// "Page X of Y" under them.
///
/// [pageBuilder] builds page `index`; a picture on it is decoded at most `decodeWidth` pixels
/// wide.
class PageTurner extends StatefulWidget {
  const PageTurner({super.key, required this.count, required this.pageBuilder})
    : assert(count > 0);

  final int count;
  final Widget Function(BuildContext context, int index, int decodeWidth)
  pageBuilder;

  @override
  State<PageTurner> createState() => _PageTurnerState();
}

class _PageTurnerState extends State<PageTurner> {
  final _pages = PageController();

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
    _zoom.dispose();
    super.dispose();
  }

  void _zoomChanged() {
    // A pinch back to full size can leave the scale a rounding error above 1.
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) {
      setState(() => _zoomed = zoomed);
    }
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                  _turn(-1),
              const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                  _turn(1),
            },
            child: Focus(
              autofocus: true,
              child: PageView.builder(
                controller: _pages,
                // Builds the page on either side as well, so the next one is loaded before it's
                // turned to.
                allowImplicitScrolling: true,
                physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
                itemCount: widget.count,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) => InteractiveViewer(
                  transformationController: _zoom,
                  minScale: 1,
                  child: widget.pageBuilder(context, index, _decodeWidth),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.small),
            child: Text(
              context.t('reader.page_of', {
                'page': _index + 1,
                'count': widget.count,
              }),
            ),
          ),
        ),
      ],
    );
  }
}
