import 'dart:async';

import 'package:bookserver/data/auth_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/form_page.dart';
import 'package:bookserver/ui/login_code_screen.dart';
import 'package:material_ui/material_ui.dart';

/// Confirms an account's email address with the mailed code, and signs in. The name and password
/// come from the screen before — sign-up, or a login the server refused until the address is
/// confirmed.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({
    super.key,
    required this.session,
    required this.usernameOrEmail,
    required this.password,
  });

  final SessionController session;
  final String usernameOrEmail;
  final String password;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _code = TextEditingController();
  var _busy = false;
  String? _errorKey;
  String? _noticeKey;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  bool get _canConfirm => !_busy && _code.text.trim().isNotEmpty;

  Future<void> _confirm() async {
    if (!_canConfirm) {
      return;
    }
    await _run(() async {
      final result = await widget.session.verifyEmail(
        widget.usernameOrEmail,
        widget.password,
        _code.text.trim(),
      );
      if (result is LoginTotpRequired && mounted) {
        unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  LoginCodeScreen(session: widget.session, challenge: result),
            ),
          ),
        );
      }
    });
  }

  Future<void> _resend() => _run(() async {
    await widget.session.resendVerificationCode(widget.usernameOrEmail);
    if (mounted) {
      setState(() => _noticeKey = 'verify_email.resent');
    }
  });

  /// Runs [action] with the screen busy, and shows its failure.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _errorKey = null;
      _noticeKey = null;
    });
    try {
      await action();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorKey = _errorKey;
    final noticeKey = _noticeKey;
    return FormPage(
      children: [
        Text(
          context.t('verify_email.title'),
          style: theme.textTheme.headlineSmall,
        ),
        Text(context.t('verify_email.explanation')),
        TextField(
          controller: _code,
          enabled: !_busy,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          autofillHints: const [AutofillHints.oneTimeCode],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _confirm(),
          decoration: InputDecoration(
            labelText: context.t('verify_email.code'),
          ),
        ),
        if (noticeKey != null) Text(context.t(noticeKey)),
        if (errorKey != null)
          Text(
            context.t(errorKey),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ListenableBuilder(
          listenable: _code,
          builder: (context, _) => FilledButton(
            onPressed: _canConfirm ? _confirm : null,
            child: Text(context.t('verify_email.submit')),
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        TextButton(
          onPressed: _busy ? null : _resend,
          child: Text(context.t('verify_email.resend')),
        ),
      ],
    );
  }
}
