import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/manage/manage_libraries_screen.dart';
import 'package:bookserver/ui/manage/manage_series_screen.dart';
import 'package:material_ui/material_ui.dart';

/// What an admin manages, one entry per list: the libraries and the series.
class ManageScreen extends StatelessWidget {
  const ManageScreen({super.key, required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('manage.title'))),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.collections_bookmark),
            title: Text(context.t('manage.libraries')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                _open(context, ManageLibrariesScreen(session: session)),
          ),
          ListTile(
            leading: const Icon(Icons.auto_stories),
            title: Text(context.t('manage.series')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, ManageSeriesScreen(session: session)),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));
}
