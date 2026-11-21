import 'package:bookserver/i18n/catalog.dart';
import 'package:material_ui/material_ui.dart';

/// Asks before deleting: the question [titleKey], what follows from it [explanationKey], and
/// Delete or Cancel. Answers true only for Delete.
Future<bool> confirmDelete(
  BuildContext context, {
  required String titleKey,
  required String explanationKey,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.t(titleKey)),
      content: Text(context.t(explanationKey)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.t('manage.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.t('manage.delete')),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
