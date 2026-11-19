import 'dart:async';

import 'package:bookserver/data/api_client.dart';
import 'package:bookserver/data/auth_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/i18n/catalog_controller.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/form_page.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:bookserver/ui/verify_email_screen.dart';
import 'package:material_ui/material_ui.dart';

/// Creates an account on the session's server, in the language the app shows.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({
    super.key,
    required this.session,
    required this.catalogs,
  });

  final SessionController session;
  final CatalogController catalogs;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  final _setupCode = TextEditingController();
  late final _typed = Listenable.merge([
    _email,
    _username,
    _password,
    _repeat,
    _setupCode,
  ]);
  var _askForSetupCode = false;
  var _busy = false;
  String? _errorKey;

  @override
  void dispose() {
    _email.dispose();
    _username.dispose();
    _password.dispose();
    _repeat.dispose();
    _setupCode.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_busy &&
      _email.text.trim().isNotEmpty &&
      _username.text.trim().isNotEmpty &&
      _password.text.isNotEmpty &&
      _repeat.text.isNotEmpty &&
      (!_askForSetupCode || _setupCode.text.trim().isNotEmpty);

  Future<void> _submit() async {
    if (!_canSubmit) {
      return;
    }
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      final result = await widget.session.signUp(
        email: _email.text.trim(),
        username: _username.text.trim(),
        password: _password.text,
        passwordRepeat: _repeat.text,
        setupCode: _askForSetupCode ? _setupCode.text.trim() : null,
        locale: widget.catalogs.serverLanguage,
      );
      if (result is VerificationRequired && mounted) {
        unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => VerifyEmailScreen(
                session: widget.session,
                usernameOrEmail: _email.text.trim(),
                password: _password.text,
              ),
            ),
          ),
        );
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          if (error case ApiException(key: 'invalid_setup_code')) {
            _askForSetupCode = true;
          }
          _errorKey = errorTextKey(error, CatalogScope.of(context));
        });
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
    final errorKey = _errorKey;
    return FormPage(
      children: [
        Text(context.t('sign_up.title'), style: theme.textTheme.headlineSmall),
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Spacing.medium,
            children: [
              TextField(
                controller: _email,
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(
                  labelText: context.t('sign_up.email'),
                ),
              ),
              TextField(
                controller: _username,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newUsername],
                decoration: InputDecoration(
                  labelText: context.t('sign_up.username'),
                  helperText: context.t('sign_up.username_rule'),
                ),
              ),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: context.t('sign_up.password'),
                  helperText: context.t('sign_up.password_rule'),
                ),
              ),
              TextField(
                controller: _repeat,
                enabled: !_busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: _askForSetupCode
                    ? TextInputAction.next
                    : TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: context.t('sign_up.password_repeat'),
                ),
              ),
            ],
          ),
        ),
        if (_askForSetupCode) ...[
          Text(context.t('sign_up.setup_code_explanation')),
          TextField(
            controller: _setupCode,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: context.t('sign_up.setup_code'),
            ),
          ),
        ],
        if (errorKey != null)
          Text(
            context.t(errorKey),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ListenableBuilder(
          listenable: _typed,
          builder: (context, _) => FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: Text(context.t('sign_up.submit')),
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
      ],
    );
  }
}
