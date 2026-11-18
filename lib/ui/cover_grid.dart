import 'dart:math' as math;

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
/// library, a series or a book.
class CoverCard extends StatelessWidget {
  const CoverCard({
    super.key,
    required this.cover,
    required this.name,
    required this.onTap,
    this.detail,
  });

  /// The cover, as wide as the card.
  final Widget cover;
  final String name;
  final VoidCallback onTap;

  /// One line under the name, such as how many books a series holds; its [CoverGrid] needs
  /// `withDetail`.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Spacing.small,
              children: [
                cover,
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
                child: InkWell(onTap: onTap),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
