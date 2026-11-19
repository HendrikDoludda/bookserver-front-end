import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/form_page.dart';
import 'package:bookserver/ui/reset_password_screen.dart';
import 'package:material_ui/material_ui.dart';

/// Asks the server to mail a password-reset code. Pops with the email address once the password
/// is changed on the next screen, so the login screen can say so.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  var _busy = false;
  String? _errorKey;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  bool get _canSend => !_busy && _email.text.trim().isNotEmpty;

  Future<void> _send() async {
    if (!_canSend) {
      return;
    }
    final email = _email.text.trim();
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      await widget.session.requestPasswordReset(email);
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _errorKey = errorTextKey(error, CatalogScope.of(context));
        });
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    final changed = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            ResetPasswordScreen(session: widget.session, email: email),
      ),
    );
    if (changed != null && mounted) {
      Navigator.of(context).pop(changed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorKey = _errorKey;
    return FormPage(
      children: [
        Text(
          context.t('password_reset.title'),
          style: theme.textTheme.headlineSmall,
        ),
        Text(context.t('password_reset.explanation')),
        TextField(
          controller: _email,
          enabled: !_busy,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _send(),
          decoration: InputDecoration(
            labelText: context.t('password_reset.email'),
          ),
        ),
        if (errorKey != null)
          Text(
            context.t(errorKey),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ListenableBuilder(
          listenable: _email,
          builder: (context, _) => FilledButton(
            onPressed: _canSend ? _send : null,
            child: Text(context.t('password_reset.send')),
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
      ],
    );
  }
}
