import 'package:bookserver/data/preferences.dart';
import 'package:bookserver/ui/platform.dart';
import 'package:bookserver/ui/preferences_scope.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

/// The frame a reader shows a book in: Back, the [title] and the reader's [controls] in bars that
/// lie over the pages and hide while reading, and [status] in a strip under the pages.
///
/// On a desktop one bar at the top holds all of it. On a phone or tablet the [controls] have a bar
/// at the bottom, gathered at the end on the side of the hand that holds the device.
class ReaderFrame extends StatefulWidget {
  const ReaderFrame({
    super.key,
    required this.title,
    required this.body,
    this.controls = const [],
    this.status,
  });

  final String title;

  /// The pages. The bars come and go over them without changing their size.
  final Widget body;

  final List<Widget> controls;

  /// Shown under the pages whether or not the bars are, such as "Page 3 of 20".
  final Widget? status;

  @override
  State<ReaderFrame> createState() => ReaderFrameState();
}

class ReaderFrameState extends State<ReaderFrame> {
  var _barShown = true;

  /// Whether the bars are on screen.
  bool get barShown => _barShown;

  void hideBar() {
    if (_barShown) {
      setState(() => _barShown = false);
    }
  }

  void toggleBar() => setState(() => _barShown = !_barShown);

  bool _scrollStarted(ScrollStartNotification notification) {
    // Only the pages' own scrolling: a table that scrolls sideways inside a page is deeper.
    if (notification.depth == 0) {
      hideBar();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final controlsBelow = isPhoneOrTablet() && widget.controls.isNotEmpty;
    final leftHanded =
        PreferencesScope.of(context).preferences.handedness == Handedness.left;
    final barHeight = AppBarTheme.of(context).toolbarHeight ?? kToolbarHeight;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: MediaQuery(
                      // As `Scaffold.extendBodyBehindAppBar` does it: a list starts clear of the
                      // bars and scrolls under them.
                      data: MediaQuery.of(context).copyWith(
                        padding: EdgeInsets.only(
                          top: barHeight,
                          bottom: controlsBelow ? barHeight : 0,
                        ),
                      ),
                      child: NotificationListener<ScrollStartNotification>(
                        onNotification: _scrollStarted,
                        child: widget.body,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _SlidingBar(
                      shown: _barShown,
                      edge: VerticalDirection.up,
                      child: AppBar(
                        title: Text(widget.title),
                        actions: controlsBelow ? null : widget.controls,
                      ),
                    ),
                  ),
                  if (controlsBelow)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: _SlidingBar(
                        shown: _barShown,
                        edge: VerticalDirection.down,
                        child: Material(
                          color: Theme.of(context).colorScheme.surfaceContainer,
                          child: SizedBox(
                            height: barHeight,
                            child: Row(
                              // By physical side: a thumb is on the left in any language.
                              textDirection: TextDirection.ltr,
                              mainAxisAlignment: leftHanded
                                  ? MainAxisAlignment.start
                                  : MainAxisAlignment.end,
                              children: widget.controls,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.status case final status?)
              Padding(
                padding: const EdgeInsets.all(Spacing.small),
                child: status,
              ),
          ],
        ),
      ),
    );
  }
}

/// A bar that slides out of view over the [edge] it sits at while not [shown], and takes no taps
/// or focus meanwhile.
class _SlidingBar extends StatelessWidget {
  const _SlidingBar({
    required this.shown,
    required this.edge,
    required this.child,
  });

  final bool shown;
  final VerticalDirection edge;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !shown,
      child: ExcludeFocus(
        excluding: !shown,
        child: AnimatedSlide(
          offset: shown
              ? Offset.zero
              : Offset(0, edge == VerticalDirection.up ? -1 : 1),
          duration: Durations.medium2,
          curve: Easing.standard,
          child: child,
        ),
      ),
    );
  }
}
