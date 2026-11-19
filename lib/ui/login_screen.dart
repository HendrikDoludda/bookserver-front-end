import 'dart:async';

import 'package:bookserver/data/api_client.dart';
import 'package:bookserver/data/auth_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/i18n/catalog_controller.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/forgot_password_screen.dart';
import 'package:bookserver/ui/form_page.dart';
import 'package:bookserver/ui/login_code_screen.dart';
import 'package:bookserver/ui/sign_up_screen.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:bookserver/ui/verify_email_screen.dart';
import 'package:material_ui/material_ui.dart';

/// Signs in to [server] with a username or email address and a password.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.session,
    required this.catalogs,
    required this.server,
    this.endedKey,
  });

  final SessionController session;
  final CatalogController catalogs;
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
  String? _noticeKey;

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
      _noticeKey = null;
    });
    try {
      final result = await widget.session.logIn(
        _name.text.trim(),
        _password.text,
      );
      if (result is LoginTotpRequired && mounted) {
        _open(LoginCodeScreen(session: widget.session, challenge: result));
      }
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      if (error case ApiException(key: 'email_not_verified')) {
        _open(
          VerifyEmailScreen(
            session: widget.session,
            usernameOrEmail: _name.text.trim(),
            password: _password.text,
          ),
        );
      } else {
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

  void _open(Widget screen) {
    unawaited(
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen)),
    );
  }

  /// Opens the password reset; once it has changed the password, fills in its email address and
  /// says so.
  Future<void> _resetPassword() async {
    final email = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(session: widget.session),
      ),
    );
    if (email != null && mounted) {
      _name.text = email;
      _password.clear();
      setState(() {
        _messageKey = null;
        _noticeKey = 'password_reset.done';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messageKey = _messageKey;
    final noticeKey = _noticeKey;
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
        if (noticeKey != null) Text(context.t(noticeKey)),
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
          onPressed: _busy ? null : _resetPassword,
          child: Text(context.t('login.forgot_password')),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => _open(
                  SignUpScreen(
                    session: widget.session,
                    catalogs: widget.catalogs,
                  ),
                ),
          child: Text(context.t('login.create_account')),
        ),
        TextButton(
          onPressed: _busy ? null : widget.session.forgetServer,
          child: Text(context.t('login.change_server')),
        ),
      ],
    );
  }
}
