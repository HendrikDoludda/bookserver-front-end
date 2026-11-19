import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/form_page.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// The recovery codes, which the server shows only this once. Only Done leaves the screen, so
/// a slip of Back can't lose them.
class RecoveryCodesScreen extends StatefulWidget {
  const RecoveryCodesScreen({super.key, required this.codes});

  final List<String> codes;

  @override
  State<RecoveryCodesScreen> createState() => _RecoveryCodesScreenState();
}

class _RecoveryCodesScreenState extends State<RecoveryCodesScreen> {
  var _copied = false;

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: widget.codes.join('\n')));
    if (mounted) {
      setState(() => _copied = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: FormPage(
        back: false,
        children: [
          Text(
            context.t('two_factor.codes_title'),
            style: theme.textTheme.headlineSmall,
          ),
          Text(context.t('two_factor.codes_explanation')),
          SelectableText(
            widget.codes.join('\n'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.merge(monospace),
          ),
          OutlinedButton(
            onPressed: _copyAll,
            child: Text(context.t('two_factor.copy_all')),
          ),
          if (_copied)
            Text(context.t('two_factor.copied'), textAlign: TextAlign.center),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('two_factor.done')),
          ),
        ],
      ),
    );
  }
}
