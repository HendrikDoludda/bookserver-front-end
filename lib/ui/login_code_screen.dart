import 'package:bookserver/data/auth_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/form_page.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// The step after a correct password for an account with two-factor authentication: a code from
/// the authenticator app, or one of the recovery codes.
class LoginCodeScreen extends StatefulWidget {
  const LoginCodeScreen({
    super.key,
    required this.session,
    required this.challenge,
  });

  final SessionController session;
  final LoginTotpRequired challenge;

  @override
  State<LoginCodeScreen> createState() => _LoginCodeScreenState();
}

class _LoginCodeScreenState extends State<LoginCodeScreen> {
  final _code = TextEditingController();
  var _recoveryCode = false;
  var _busy = false;
  String? _errorKey;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  bool get _canSignIn => !_busy && _code.text.trim().isNotEmpty;

  Future<void> _signIn() async {
    if (!_canSignIn) {
      return;
    }
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      await widget.session.logInWithCode(
        widget.challenge,
        _code.text.trim(),
        recoveryCode: _recoveryCode,
      );
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _errorKey = errorTextKey(error, CatalogScope.of(context)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _switchKind() {
    _code.clear();
    setState(() {
      _recoveryCode = !_recoveryCode;
      _errorKey = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorKey = _errorKey;
    return FormPage(
      children: [
        Text(
          context.t('login_code.title'),
          style: theme.textTheme.headlineSmall,
        ),
        Text(
          context.t(
            _recoveryCode
                ? 'login_code.recovery_explanation'
                : 'login_code.app_explanation',
          ),
        ),
        TextField(
          // A new key per kind, so the keyboard and autofill change with it.
          key: ValueKey(_recoveryCode),
          controller: _code,
          enabled: !_busy,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: _recoveryCode
              ? TextInputType.visiblePassword
              : TextInputType.number,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: _recoveryCode
              ? null
              : [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
          autofillHints: _recoveryCode
              ? null
              : const [AutofillHints.oneTimeCode],
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _signIn(),
          decoration: InputDecoration(
            labelText: context.t(
              _recoveryCode
                  ? 'login_code.recovery_code'
                  : 'login_code.app_code',
            ),
          ),
        ),
        if (errorKey != null)
          Text(
            context.t(errorKey),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        FilledButton(
          onPressed: _canSignIn ? _signIn : null,
          child: Text(context.t('login.sign_in')),
        ),
        if (_busy) const LinearProgressIndicator(),
        TextButton(
          onPressed: _busy ? null : _switchKind,
          child: Text(
            context.t(
              _recoveryCode
                  ? 'login_code.use_app_code'
                  : 'login_code.use_recovery_code',
            ),
          ),
        ),
      ],
    );
  }
}
