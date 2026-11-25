import 'dart:math' as math;

import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

/// Cover cards in a grid: as many columns as the width takes, none wider than
/// [Covers.maxTileWidth].
class CoverGrid extends StatelessWidget {
  const CoverGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.withDetail = false,
  });

  /// The lines a card's name gets; a longer one ends in "…".
  static const nameLines = 2;

  final int itemCount;

  /// Builds the card at an index: a [CoverCard].
  final IndexedWidgetBuilder itemBuilder;

  /// Whether the cards show a [CoverCard.detail] under their name, which every card gets room for.
  final bool withDetail;

  @override
  Widget build(BuildContext context) {
    final padding =
        MediaQuery.paddingOf(context) + const EdgeInsets.all(Spacing.medium);
    final textHeight =
        _heightOfLines(context, nameLines, DefaultTextStyle.of(context).style) +
        (withDetail ? _heightOfLines(context, 1, _detailStyle(context)) : 0);
    // Flutter's grid layouts make a tile's height either fixed or a share of its width; a card is
    // both: its cover grows with the width, its name doesn't.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(0.0, constraints.maxWidth - padding.horizontal);
        final columns = math.max(
          1,
          ((width + Spacing.medium) / (Covers.maxTileWidth + Spacing.medium))
              .ceil(),
        );
        final cardWidth = (width - Spacing.medium * (columns - 1)) / columns;
        return GridView.builder(
          padding: padding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: Spacing.medium,
            crossAxisSpacing: Spacing.medium,
            mainAxisExtent:
                cardWidth / Covers.aspectRatio + Spacing.small + textHeight,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      },
    );
  }
}

/// A cover with its name under it, and a detail under that if given, tapped as one button: a
/// library, a series or a book. The cover shows how far the user has read along its bottom edge,
/// or a check once they finished.
class CoverCard extends StatelessWidget {
  const CoverCard({
    super.key,
    required this.cover,
    required this.name,
    required this.onTap,
    this.detail,
    this.progress,
    this.finished = false,
    this.onLongPress,
  });

  /// The cover, as wide as the card.
  final Widget cover;
  final String name;

  /// What a tap does; null shows the card can't be tapped.
  final VoidCallback? onTap;

  /// One line under the name, such as how many books a series holds; its [CoverGrid] needs
  /// `withDetail`.
  final String? detail;

  /// How far the user has read, from 0 to 1; null shows no bar.
  final double? progress;

  /// Whether the user finished it, which shows a check in place of the bar.
  final bool finished;

  /// What a long press or a right click does, such as a menu of the card's actions.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    final progress = this.progress;
    final colors = Theme.of(context).colorScheme;
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: onTap != null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Spacing.small,
              children: [
                Stack(
                  children: [
                    cover,
                    if (finished)
                      Positioned(
                        top: Spacing.small,
                        right: Spacing.small,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.surface,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_circle,
                            color: colors.primary,
                            semanticLabel: context.t('browse.finished'),
                          ),
                        ),
                      )
                    else if (progress != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(value: progress),
                      ),
                  ],
                ),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: CoverGrid.nameLines,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (detail != null)
                        Text(
                          detail,
                          style: _detailStyle(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            // Ink is drawn on the Material below a widget, where the cover would hide it.
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onTap,
                  onLongPress: onLongPress,
                  onSecondaryTap: onLongPress,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the card of a series or a library shows of its [count] books, [finished] of them read: a
/// bar while some are, the check once all are.
({double? progress, bool finished}) finishedShare(int finished, int count) {
  if (count > 0 && finished >= count) {
    return (progress: null, finished: true);
  }
  if (finished > 0) {
    return (progress: finished / count, finished: false);
  }
  return (progress: null, finished: false);
}

/// The style of a [CoverCard.detail]: smaller and quieter than the name.
TextStyle _detailStyle(BuildContext context) {
  final theme = Theme.of(context);
  return DefaultTextStyle.of(context).style
      .merge(theme.textTheme.bodySmall)
      .copyWith(color: theme.colorScheme.onSurfaceVariant);
}

/// How tall [lines] lines of text in [style] are, at the user's text size.
double _heightOfLines(BuildContext context, int lines, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: List.filled(lines, 'M').join('\n'), style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final height = painter.height;
  painter.dispose();
  return height;
}
