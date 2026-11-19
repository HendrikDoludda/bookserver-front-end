import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/form_page.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

/// Sets a new password for [email] with the mailed code, and pops with [email] once it's changed.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.session,
    required this.email,
  });

  final SessionController session;
  final String email;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  late final _typed = Listenable.merge([_code, _password, _repeat]);
  var _busy = false;
  String? _errorKey;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_busy &&
      _code.text.trim().isNotEmpty &&
      _password.text.isNotEmpty &&
      _repeat.text.isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) {
      return;
    }
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      await widget.session.resetPassword(
        email: widget.email,
        code: _code.text.trim(),
        newPassword: _password.text,
        newPasswordRepeat: _repeat.text,
      );
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _errorKey = errorTextKey(error, CatalogScope.of(context));
        });
      }
      return;
    }
    if (mounted) {
      Navigator.of(context).pop(widget.email);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorKey = _errorKey;
    return FormPage(
      children: [
        Text(
          context.t('password_reset.new_title'),
          style: theme.textTheme.headlineSmall,
        ),
        Text(context.t('password_reset.new_explanation')),
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Spacing.medium,
            children: [
              TextField(
                controller: _code,
                enabled: !_busy,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                autofillHints: const [AutofillHints.oneTimeCode],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: context.t('password_reset.code'),
                ),
              ),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: context.t('password_reset.new_password'),
                  helperText: context.t('password_reset.password_rule'),
                ),
              ),
              TextField(
                controller: _repeat,
                enabled: !_busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: context.t('password_reset.new_password_repeat'),
                ),
              ),
            ],
          ),
        ),
        if (errorKey != null)
          Text(
            context.t(errorKey),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ListenableBuilder(
          listenable: _typed,
          builder: (context, _) => FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: Text(context.t('password_reset.submit')),
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
      ],
    );
  }
}
