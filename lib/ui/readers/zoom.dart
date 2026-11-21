import 'package:bookserver/i18n/catalog.dart';
import 'package:material_ui/material_ui.dart';

/// A set zoom: the whole page in the window, the page's width across it, or 150, 200 or 300 % of
/// the whole page.
enum ZoomStep {
  fitPage,
  fitWidth,
  x150,
  x200,
  x300;

  /// For a multiple of the whole page, how many times it; null for a fit.
  double? get times => switch (this) {
    fitPage || fitWidth => null,
    x150 => 1.5,
    x200 => 2,
    x300 => 3,
  };
}

/// Where a page of [shape] — its width divided by its height — shows at [step] in [window], as a
/// transform of the page fitted whole and centred in it. The page's top is in view and, where it is
/// wider than the window, the side reading starts on: the right one when [rightToLeft].
Matrix4 zoomOf(
  ZoomStep step,
  double shape,
  Size window, {
  bool rightToLeft = false,
}) {
  final page = _fittedPage(shape, window);
  if (page == null) {
    return Matrix4.identity();
  }
  final scale =
      step.times ??
      (step == ZoomStep.fitWidth ? window.width / page.width : 1.0);
  final width = page.width * scale;
  final height = page.height * scale;
  final x = width <= window.width
      ? (window.width - width) / 2
      : (rightToLeft ? window.width - width : 0.0);
  final y = height <= window.height ? (window.height - height) / 2 : 0.0;
  return Matrix4.diagonal3Values(scale, scale, 1)
    ..setTranslationRaw(x - scale * page.left, y - scale * page.top, 0);
}

/// [matrix] moved as little as it takes to keep a page of [shape], fitted whole in [window], on
/// screen: where the page is larger than the window, across or down, it stops at its edges; where
/// it is smaller, it stays centred.
Matrix4 keepOnPage(Matrix4 matrix, double shape, Size window) {
  final page = _fittedPage(shape, window);
  if (page == null) {
    return matrix;
  }
  final scale = matrix.getMaxScaleOnAxis();
  final moved = matrix.getTranslation();
  double kept(double by, double start, double extent, double room) {
    final shownStart = scale * start + by;
    final shownExtent = scale * extent;
    final wanted = shownExtent <= room
        ? (room - shownExtent) / 2
        : shownStart.clamp(room - shownExtent, 0.0);
    return by + (wanted - shownStart);
  }

  final x = kept(moved.x, page.left, page.width, window.width);
  final y = kept(moved.y, page.top, page.height, window.height);
  if (x == moved.x && y == moved.y) {
    return matrix;
  }
  return matrix.clone()..setTranslationRaw(x, y, moved.z);
}

/// Where a page of [shape] lies fitted whole and centred in [window]; null while the window isn't
/// laid out, or for a page without a shape.
Rect? _fittedPage(double shape, Size window) {
  if (window.isEmpty || !(shape > 0) || shape.isInfinite) {
    return null;
  }
  final size = shape > window.aspectRatio
      ? Size(window.width, window.width / shape)
      : Size(window.height * shape, window.height);
  return Alignment.center.inscribe(size, Offset.zero & window);
}

/// The reader bar's zoom dropdown: its menu offers the steps, with [step] — the one on screen —
/// checked, and none after a pinch, when [step] is null.
class ZoomButton extends StatelessWidget {
  const ZoomButton({super.key, required this.step, required this.onChanged});

  final ZoomStep? step;
  final ValueChanged<ZoomStep> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ZoomStep>(
      icon: const Icon(Icons.zoom_in),
      tooltip: context.t('reader.zoom'),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final each in ZoomStep.values)
          CheckedPopupMenuItem(
            value: each,
            checked: each == step,
            child: Text(_label(context, each)),
          ),
      ],
    );
  }
}

String _label(BuildContext context, ZoomStep step) => switch (step) {
  ZoomStep.fitPage => context.t('reader.zoom_fit_page'),
  ZoomStep.fitWidth => context.t('reader.zoom_fit_width'),
  ZoomStep.x150 || ZoomStep.x200 || ZoomStep.x300 => context.t(
    'reader.percent',
    {'percent': (step.times! * 100).round()},
  ),
};
