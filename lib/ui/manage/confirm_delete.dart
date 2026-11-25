import 'package:bookserver/i18n/catalog.dart';
import 'package:material_ui/material_ui.dart';

/// Asks before deleting: the question [titleKey], what follows from it [explanationKey], and
/// [confirmKey] — Delete unless given — or Cancel. Answers true only for [confirmKey]. [values]
/// fill the placeholders of the question and the explanation.
Future<bool> confirmDelete(
  BuildContext context, {
  required String titleKey,
  required String explanationKey,
  String confirmKey = 'manage.delete',
  Map<String, Object> values = const {},
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.t(titleKey, values)),
      content: Text(context.t(explanationKey, values)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.t('manage.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.t(confirmKey)),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
