import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/ui/server_image.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

/// The cover of a book, a series or a library in the shape of a book cover; a placeholder while
/// it loads, and in its place when there is none.
class Cover extends StatelessWidget {
  const Cover({
    super.key,
    required this.session,
    required this.kind,
    required this.id,
  });

  final SessionController session;
  final CoverKind kind;
  final int id;

  /// The image a [Cover] shows, as the image cache knows it.
  static ImageProvider imageOf(
    SessionController session,
    CoverKind kind,
    int id,
  ) => ResizeImage(
    ServerImage(session, coverPath(kind, id)),
    width: Covers.decodeWidth,
  );

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: Covers.aspectRatio,
      child: Image(
        image: imageOf(session, kind, id),
        fit: BoxFit.cover,
        // The title next to the cover says what it shows.
        excludeFromSemantics: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
            wasSynchronouslyLoaded || frame != null
            ? child
            : const _Placeholder(),
        errorBuilder: (context, error, stackTrace) => const _Placeholder(),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.auto_stories_outlined,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}
