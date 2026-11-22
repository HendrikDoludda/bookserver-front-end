import 'package:bookserver/data/manage_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/list_screen.dart';
import 'package:bookserver/ui/manage/confirm_delete.dart';
import 'package:bookserver/ui/manage/directory_form_screen.dart';
import 'package:material_ui/material_ui.dart';

/// A folder the server scans, with the name of the library its series join; null for none.
typedef ListedDirectory = ({ManagedDirectory directory, String? libraryName});

/// Every folder the server scans, to add or remove one.
class ManageDirectoriesScreen extends StatefulWidget {
  const ManageDirectoriesScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<ManageDirectoriesScreen> createState() =>
      _ManageDirectoriesScreenState();
}

class _ManageDirectoriesScreenState extends State<ManageDirectoriesScreen> {
  // A new key gives the list a new state, which loads the folders again.
  var _generation = 0;
  var _removing = false;

  Future<List<ListedDirectory>> _load() =>
      widget.session.authorized((api, token) async {
        final manage = ManageApi(api);
        final directories = await manage.directories(token);
        final names = {
          for (final library in await manage.libraries(token))
            library.id: library.name,
        };
        return [
          for (final directory in directories)
            (directory: directory, libraryName: names[directory.libraryId]),
        ];
      });

  /// Opens the form for a new folder, and loads the list again once it added one.
  Future<void> _add() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DirectoryFormScreen(session: widget.session),
      ),
    );
    if (added == true && mounted) {
      setState(() => _generation++);
    }
  }

  Future<void> _remove(ManagedDirectory directory) async {
    final confirmed = await confirmDelete(
      context,
      titleKey: 'manage.remove_folder',
      explanationKey: 'manage.remove_folder_explanation',
      confirmKey: 'manage.remove',
    );
    if (!confirmed || !mounted) {
      return;
    }
    // Taken now: the screen may be closed by the time the removal fails.
    final messenger = ScaffoldMessenger.of(context);
    final catalog = CatalogScope.of(context);
    setState(() => _removing = true);
    try {
      await widget.session.authorized(
        (api, token) => ManageApi(api).removeDirectory(token, directory.id),
      );
      if (mounted) {
        setState(() => _generation++);
      }
    } on Exception catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(catalog.text(errorTextKey(error, catalog)))),
        );
    } finally {
      if (mounted) {
        setState(() => _removing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListScreen<ListedDirectory>(
      key: ValueKey(_generation),
      title: context.t('manage.folders'),
      emptyKey: 'manage.folders_empty',
      reloadKey: 'manage.reload',
      load: _load,
      actions: [
        IconButton(
          icon: const Icon(Icons.create_new_folder),
          tooltip: context.t('manage.add_folder'),
          onPressed: _add,
        ),
      ],
      builder: (context, listed) => ListView(
        children: [
          for (final (:directory, :libraryName) in listed)
            ListTile(
              leading: const Icon(Icons.folder),
              title: Text(directory.path),
              subtitle: Text(switch (libraryName) {
                final name? => context.t('manage.folder_library', {
                  'library': name,
                }),
                null => context.t('manage.folder_no_library'),
              }),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: context.t('manage.remove'),
                onPressed: _removing ? null : () => _remove(directory),
              ),
            ),
        ],
      ),
    );
  }
}
