import 'package:bookserver/data/manage_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/manage/library_form_screen.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

/// Adds a folder for the server to scan: its full path on the server, and whether it gets a library
/// of its own — of the type chosen, named after the folder unless another name is typed. Adding
/// closes the form with `true`.
class DirectoryFormScreen extends StatefulWidget {
  const DirectoryFormScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<DirectoryFormScreen> createState() => _DirectoryFormScreenState();
}

class _DirectoryFormScreenState extends State<DirectoryFormScreen> {
  final _path = TextEditingController();
  final _name = TextEditingController();
  var _ownLibrary = true;
  var _type = LibraryType.books;

  /// Whether a library name is typed; until then, and once it is cleared, the name follows the
  /// folder's.
  var _nameTyped = false;

  var _busy = false;
  String? _errorKey;

  @override
  void dispose() {
    _path.dispose();
    _name.dispose();
    super.dispose();
  }

  void _pathChanged(String path) {
    if (!_nameTyped) {
      _name.text = folderName(path);
    }
  }

  Future<void> _add() async {
    final path = _path.text;
    final name = _name.text.trim();
    final type = _ownLibrary ? _type : null;
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      await widget.session.authorized(
        (api, token) => ManageApi(api).addDirectory(
          token,
          path: path,
          libraryType: type,
          // Without one, the server names the library after the folder.
          libraryName: type != null && name.isNotEmpty ? name : null,
        ),
      );
      if (mounted) {
        Navigator.of(context).pop(true);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('manage.add_folder')),
        actions: [
          TextButton(
            onPressed: _busy ? null : _add,
            child: Text(context.t('manage.add')),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Widths.form),
              child: ListView(
                padding: const EdgeInsets.all(Spacing.medium),
                children: [
                  if (_errorKey case final errorKey?)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.medium),
                      child: Text(
                        context.t(errorKey),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  TextField(
                    controller: _path,
                    enabled: !_busy,
                    onChanged: _pathChanged,
                    decoration: InputDecoration(
                      labelText: context.t('manage.folder_path'),
                      helperText: context.t('manage.folder_path_help'),
                      helperMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: Spacing.medium),
                  SwitchListTile(
                    value: _ownLibrary,
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.t('manage.own_library')),
                    subtitle: Text(
                      context.t(
                        _ownLibrary
                            ? 'manage.own_library_on'
                            : 'manage.own_library_off',
                      ),
                    ),
                    onChanged: _busy
                        ? null
                        : (on) => setState(() => _ownLibrary = on),
                  ),
                  if (_ownLibrary) ...[
                    const SizedBox(height: Spacing.medium),
                    TextField(
                      controller: _name,
                      enabled: !_busy,
                      onChanged: (name) => _nameTyped = name.isNotEmpty,
                      decoration: InputDecoration(
                        labelText: context.t('manage.library_name'),
                      ),
                    ),
                    const SizedBox(height: Spacing.medium),
                    DropdownButtonFormField<LibraryType>(
                      initialValue: _type,
                      decoration: InputDecoration(
                        labelText: context.t('manage.type'),
                      ),
                      items: [
                        for (final type in LibraryType.values)
                          DropdownMenuItem(
                            value: type,
                            child: Text(context.t(typeTextKey(type))),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (type) => setState(() => _type = type ?? _type),
                    ),
                  ],
                  const SizedBox(height: Spacing.large),
                  Text(
                    context.t('manage.folder_scanned'),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          if (_busy)
            const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

/// The last part of [path], the folder's own name — `Manga` for `/books/Manga/` — in a path
/// written with `/` or, on a Windows server, `\`.
String folderName(String path) => path
    .split(RegExp(r'[/\\]'))
    .lastWhere((part) => part.isNotEmpty, orElse: () => '');
