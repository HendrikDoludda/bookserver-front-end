import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/data/two_factor_api.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/form_page.dart';
import 'package:bookserver/ui/platform.dart';
import 'package:bookserver/ui/qr_code.dart';
import 'package:bookserver/ui/recovery_codes_screen.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [link] in the app that handles it; `false` when no app does.
typedef OpenLink = Future<bool> Function(Uri link);

Future<bool> _openExternally(Uri link) =>
    launchUrl(link, mode: LaunchMode.externalApplication);

/// Turns two-factor authentication on: starts a setup, shows it as a QR code and as a setup key,
/// and turns it on with a code from the app and the password. Goes on to the recovery codes.
class TwoFactorSetupScreen extends StatefulWidget {
  const TwoFactorSetupScreen({
    super.key,
    required this.session,
    this.openLink = _openExternally,
  });

  final SessionController session;
  final OpenLink openLink;

  @override
  State<TwoFactorSetupScreen> createState() => _TwoFactorSetupScreenState();
}

class _TwoFactorSetupScreenState extends State<TwoFactorSetupScreen> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  late final _typed = Listenable.merge([_code, _password]);
  TwoFactorSetup? _setup;
  var _busy = true;
  String? _errorKey;
  String? _noticeKey;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  // A phone can't scan its own screen; it opens the link in its authenticator app instead.
  bool get _onPhone => isPhoneOrTablet();

  bool get _canConfirm =>
      !_busy &&
      _setup != null &&
      _code.text.length == 6 &&
      _password.text.isNotEmpty;

  Future<void> _start() => _run(() async {
    final setup = await widget.session.authorized(
      (api, token) => TwoFactorApi(api).start(token),
    );
    if (mounted) {
      setState(() => _setup = setup);
    }
  });

  void _restart() {
    setState(() => _busy = true);
    _start();
  }

  Future<void> _confirm() async {
    if (!_canConfirm) {
      return;
    }
    final code = _code.text;
    final password = _password.text;
    setState(() => _busy = true);
    await _run(() async {
      final codes = await widget.session.authorized(
        (api, token) =>
            TwoFactorApi(api).confirm(token, code: code, password: password),
      );
      if (mounted) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => RecoveryCodesScreen(codes: codes),
          ),
        );
      }
    });
  }

  /// Runs [action] with the screen busy, and shows its failure.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
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

  Future<void> _copySecret(TwoFactorSetup setup) async {
    await Clipboard.setData(ClipboardData(text: setup.secret));
    if (mounted) {
      setState(() => _noticeKey = 'two_factor.copied');
    }
  }

  Future<void> _openInApp(TwoFactorSetup setup) async {
    bool opened;
    try {
      opened = await widget.openLink(Uri.parse(setup.otpauthUrl));
    } on Exception {
      opened = false;
    }
    if (!opened && mounted) {
      setState(() => _noticeKey = 'two_factor.no_app');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final setup = _setup;
    final errorKey = _errorKey;
    final noticeKey = _noticeKey;
    return FormPage(
      children: [
        Text(
          context.t('two_factor.setup_title'),
          style: theme.textTheme.headlineSmall,
        ),
        if (setup != null) ...[
          Text(context.t('two_factor.setup_explanation')),
          QrCodeView(data: setup.otpauthUrl),
          Text(
            context.t('two_factor.secret'),
            style: theme.textTheme.labelLarge,
          ),
          SelectableText(setup.secret, style: monospace),
          Wrap(
            spacing: Spacing.small,
            runSpacing: Spacing.small,
            children: [
              OutlinedButton(
                onPressed: () => _copySecret(setup),
                child: Text(context.t('two_factor.copy')),
              ),
              if (_onPhone)
                OutlinedButton(
                  onPressed: () => _openInApp(setup),
                  child: Text(context.t('two_factor.open_in_app')),
                ),
            ],
          ),
          if (noticeKey != null) Text(context.t(noticeKey)),
          TextField(
            controller: _code,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            autofillHints: const [AutofillHints.oneTimeCode],
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: context.t('two_factor.code'),
            ),
          ),
          TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _confirm(),
            decoration: InputDecoration(
              labelText: context.t('two_factor.password'),
            ),
          ),
        ],
        if (errorKey != null)
          Text(
            context.t(errorKey),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        if (setup == null && errorKey != null)
          FilledButton.tonal(
            onPressed: _busy ? null : _restart,
            child: Text(context.t('settings.reload')),
          ),
        if (setup != null)
          ListenableBuilder(
            listenable: _typed,
            builder: (context, _) => FilledButton(
              onPressed: _canConfirm ? _confirm : null,
              child: Text(context.t('two_factor.confirm')),
            ),
          ),
        if (_busy) const LinearProgressIndicator(),
      ],
    );
  }
}
