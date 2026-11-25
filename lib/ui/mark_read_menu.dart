import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:material_ui/material_ui.dart';

/// Offers to mark [book] read, or unread once it is, in a menu over the card [cardContext] built;
/// once the server has it, [onMarked] runs. A save the server refuses says so.
Future<void> offerMark(
  BuildContext cardContext,
  SessionController session,
  Book book, {
  required VoidCallback onMarked,
}) async {
  final card = cardContext.findRenderObject()! as RenderBox;
  final overlay =
      Overlay.of(cardContext).context.findRenderObject()! as RenderBox;
  final read = !book.progress.finished;
  final chosen = await showMenu<bool>(
    context: cardContext,
    position: RelativeRect.fromRect(
      card.localToGlobal(Offset.zero, ancestor: overlay) & card.size,
      Offset.zero & overlay.size,
    ),
    items: [
      PopupMenuItem(
        value: read,
        child: Text(
          cardContext.t(read ? 'browse.mark_read' : 'browse.mark_unread'),
        ),
      ),
    ],
  );
  if (chosen == null || !cardContext.mounted) {
    return;
  }
  // Taken before the wait: the card may be gone by the time the save fails.
  final messenger = ScaffoldMessenger.of(cardContext);
  final notSaved = cardContext.t('browse.mark_not_saved');
  try {
    await session.authorized(
      (api, sessionToken) =>
          BrowseApi(api).saveProgress(book.id, sessionToken, finished: chosen),
    );
    onMarked();
  } on Exception {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(notSaved)));
  }
}
