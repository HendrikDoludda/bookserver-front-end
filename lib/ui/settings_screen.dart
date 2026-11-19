import 'package:bookserver/data/locales_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/data/settings_api.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/i18n/catalog_controller.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/notice.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

// The device-language entry's value in the list: no language code is empty.
const _followDevice = '';

/// The signed-in user's settings: the language the app shows, saved on the server so every
/// device and every mail use it.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.session,
    required this.catalogs,
  });

  final SessionController session;
  final CatalogController catalogs;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  var _loading = true;
  String? _loadErrorKey;
  List<OfferedLanguage>? _languages;

  /// The texts of the "Device language" entry, in the language choosing it shows, so someone who
  /// can't read the language on screen still finds the way back — as each language's own name
  /// lets them find theirs.
  Catalog? _deviceTexts;

  /// The language setting: a language's code, or [_followDevice].
  var _choice = _followDevice;
  var _saving = false;
  String? _saveErrorKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _reload() {
    setState(() => _loading = true);
    _load();
  }

  Future<void> _load() async {
    try {
      final (languages, setting) = await widget.session.authorized(
        (api, token) async => (
          await LocalesApi(api).languages(),
          await SettingsApi(api).language(token),
        ),
      );
      final catalogs = widget.catalogs;
      final deviceLanguage = catalogs.deviceLanguage(languages);
      final deviceTexts = deviceLanguage == null
          ? catalogs.catalog
          : await catalogs.catalogIn(deviceLanguage);
      if (mounted) {
        setState(() {
          _languages = languages;
          _deviceTexts = deviceTexts;
          _choice = setting ?? _followDevice;
          _loadErrorKey = null;
        });
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _loadErrorKey = errorTextKey(error, CatalogScope.of(context)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Saves [choice] and shows the app in it; a refusal puts the choice back and says why.
  Future<void> _choose(String? choice) async {
    if (choice == null || choice == _choice || _saving) {
      return;
    }
    final before = _choice;
    setState(() {
      _choice = choice;
      _saving = true;
      _saveErrorKey = null;
    });
    try {
      await widget.session.authorized(
        (api, token) =>
            SettingsApi(api)
                .setLanguage(token, choice == _followDevice ? null : choice),
      );
      await widget.catalogs.pickAgain();
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _choice = before;
          _saveErrorKey = errorTextKey(error, CatalogScope.of(context));
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('settings.title'))),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _content(context),
          if (_loading || _saving)
            const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    if (_loadErrorKey case final errorKey?) {
      return Notice(
        text: context.t(errorKey),
        color: theme.colorScheme.error,
        action: FilledButton.tonal(
          onPressed: _loading ? null : _reload,
          child: Text(context.t('settings.reload')),
        ),
      );
    }
    final languages = _languages;
    if (languages == null) {
      return const SizedBox.shrink();
    }
    final saveErrorKey = _saveErrorKey;
    final deviceTexts = _deviceTexts ?? CatalogScope.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Widths.form),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: Spacing.medium),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.medium),
              child: Text(
                context.t('settings.language'),
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (saveErrorKey != null)
              Padding(
                padding: const EdgeInsets.all(Spacing.medium),
                child: Text(
                  context.t(saveErrorKey),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            RadioGroup<String>(
              groupValue: _choice,
              onChanged: _choose,
              child: Column(
                children: [
                  RadioListTile<String>(
                    value: _followDevice,
                    enabled: !_saving,
                    controlAffinity: ListTileControlAffinity.trailing,
                    secondary: const Icon(Icons.devices),
                    title: Text(deviceTexts.text('settings.device_language')),
                    subtitle: Text(
                      deviceTexts.text('settings.device_language_explanation'),
                    ),
                  ),
                  for (final language in languages)
                    RadioListTile<String>(
                      value: language.code,
                      enabled: !_saving,
                      controlAffinity: ListTileControlAffinity.trailing,
                      secondary: _LanguageIcon(language.icon),
                      title: Text(language.displayName),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A language's emoji in the space of an icon, so the names line up with or without one.
class _LanguageIcon extends StatelessWidget {
  const _LanguageIcon(this.icon);

  final String? icon;

  @override
  Widget build(BuildContext context) {
    final size = IconTheme.of(context).size;
    return SizedBox(
      width: size,
      child: Text(
        icon ?? '',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: size),
      ),
    );
  }
}
