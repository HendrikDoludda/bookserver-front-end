import 'package:bookserver/data/manage_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/list_screen.dart';
import 'package:bookserver/ui/manage/library_form_screen.dart';
import 'package:material_ui/material_ui.dart';

/// Every library, to create, edit or delete one.
class ManageLibrariesScreen extends StatefulWidget {
  const ManageLibrariesScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<ManageLibrariesScreen> createState() => _ManageLibrariesScreenState();
}

class _ManageLibrariesScreenState extends State<ManageLibrariesScreen> {
  // A new key gives the list a new state, which loads the libraries again.
  var _generation = 0;

  /// Opens the form for [library], or for a new one, and loads the list again once it saved.
  Future<void> _open(ManagedLibrary? library) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            LibraryFormScreen(session: widget.session, library: library),
      ),
    );
    if (saved == true && mounted) {
      setState(() => _generation++);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListScreen<ManagedLibrary>(
      key: ValueKey(_generation),
      title: context.t('manage.libraries'),
      emptyKey: 'manage.libraries_empty',
      reloadKey: 'manage.reload',
      load: () => widget.session.authorized(
        (api, token) => ManageApi(api).libraries(token),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: context.t('manage.new_library'),
          onPressed: () => _open(null),
        ),
      ],
      builder: (context, libraries) => ListView(
        children: [
          for (final library in libraries)
            ListTile(
              title: Text(library.name),
              subtitle: Text(
                context.plural('browse.series_count', library.seriesCount),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(library),
            ),
        ],
      ),
    );
  }
}
