import 'package:bookserver/data/auth_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/form_page.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

/// Signs in to [server] with a username or email address and a password.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.session,
    required this.server,
    this.endedKey,
  });

  final SessionController session;
  final Uri server;

  /// Why the last session ended, when the server ended it.
  final String? endedKey;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  late final _typed = Listenable.merge([_name, _password]);
  var _busy = false;
  late String? _messageKey = widget.endedKey;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  // An empty attempt would still count against the server's limit of failed logins.
  bool get _canSignIn =>
      !_busy && _name.text.trim().isNotEmpty && _password.text.isNotEmpty;

  Future<void> _signIn() async {
    if (!_canSignIn) {
      return;
    }
    setState(() {
      _busy = true;
      _messageKey = null;
    });
    try {
      final result = await widget.session.logIn(
        _name.text.trim(),
        _password.text,
      );
      if (result is LoginTotpRequired && mounted) {
        setState(() => _messageKey = 'login.totp_unavailable');
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _messageKey = errorTextKey(error, CatalogScope.of(context)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messageKey = _messageKey;
    return FormPage(
      children: [
        Text(context.t('login.title'), style: theme.textTheme.headlineSmall),
        Text(
          widget.server.authority,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Spacing.medium,
            children: [
              TextField(
                controller: _name,
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                decoration: InputDecoration(
                  labelText: context.t('login.username_or_email'),
                ),
              ),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _signIn(),
                decoration: InputDecoration(
                  labelText: context.t('login.password'),
                ),
              ),
            ],
          ),
        ),
        if (messageKey != null)
          Text(
            context.t(messageKey),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ListenableBuilder(
          listenable: _typed,
          builder: (context, _) => FilledButton(
            onPressed: _canSignIn ? _signIn : null,
            child: Text(context.t('login.sign_in')),
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        TextButton(
          onPressed: _busy ? null : widget.session.forgetServer,
          child: Text(context.t('login.change_server')),
        ),
      ],
    );
  }
}
