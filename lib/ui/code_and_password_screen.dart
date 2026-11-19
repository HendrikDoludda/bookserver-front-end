import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/data/two_factor_api.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/form_page.dart';
import 'package:bookserver/ui/recovery_codes_screen.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

/// What the password and a second-factor code confirm.
enum TwoFactorAction {
  /// New recovery codes in place of the old ones.
  renewCodes,

  /// Two-factor authentication off, which signs the user out everywhere.
  turnOff,
}

/// Asks for the password and a code from the authenticator app or a recovery code, then does
/// [action]: new codes go on to the codes screen; turning off signs out to the login screen.
class CodeAndPasswordScreen extends StatefulWidget {
  const CodeAndPasswordScreen({
    super.key,
    required this.session,
    required this.action,
  });

  final SessionController session;
  final TwoFactorAction action;

  @override
  State<CodeAndPasswordScreen> createState() => _CodeAndPasswordScreenState();
}

class _CodeAndPasswordScreenState extends State<CodeAndPasswordScreen> {
  final _password = TextEditingController();
  final _code = TextEditingController();
  late final _typed = Listenable.merge([_password, _code]);
  var _busy = false;
  String? _errorKey;

  @override
  void dispose() {
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_busy && _password.text.isNotEmpty && _code.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) {
      return;
    }
    final password = _password.text;
    final code = _code.text.trim();
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      switch (widget.action) {
        case TwoFactorAction.renewCodes:
          final codes = await widget.session.authorized(
            (api, token) =>
                TwoFactorApi(api)
                    .renewRecoveryCodes(token, password: password, code: code),
          );
          if (mounted) {
            await Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => RecoveryCodesScreen(codes: codes),
              ),
            );
          }
        case TwoFactorAction.turnOff:
          await widget.session.authorized(
            (api, token) =>
                TwoFactorApi(api)
                    .disable(token, password: password, code: code),
          );
          await widget.session.logOut(noticeKey: 'two_factor.off_done');
      }
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
    final (title, explanation, submit) = switch (widget.action) {
      TwoFactorAction.renewCodes => (
        'two_factor.renew',
        'two_factor.renew_explanation',
        'two_factor.renew',
      ),
      TwoFactorAction.turnOff => (
        'two_factor.off_title',
        'two_factor.off_explanation',
        'two_factor.turn_off',
      ),
    };
    return FormPage(
      children: [
        Text(context.t(title), style: theme.textTheme.headlineSmall),
        Text(context.t(explanation)),
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Spacing.medium,
            children: [
              TextField(
                controller: _password,
                enabled: !_busy,
                autofocus: true,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: context.t('two_factor.password'),
                ),
              ),
              TextField(
                controller: _code,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                autofillHints: const [AutofillHints.oneTimeCode],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: context.t('two_factor.code_or_recovery'),
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
            child: Text(context.t(submit)),
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
      ],
    );
  }
}
