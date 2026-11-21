import 'package:bookserver/data/manage_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/list_screen.dart';
import 'package:bookserver/ui/manage/series_form_screen.dart';
import 'package:material_ui/material_ui.dart';

/// Every series, to edit or delete one.
class ManageSeriesScreen extends StatefulWidget {
  const ManageSeriesScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<ManageSeriesScreen> createState() => _ManageSeriesScreenState();
}

class _ManageSeriesScreenState extends State<ManageSeriesScreen> {
  // A new key gives the list a new state, which loads the series again.
  var _generation = 0;

  /// Opens the form for [series], and loads the list again once it saved.
  Future<void> _open(ManagedSeries series) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            SeriesFormScreen(session: widget.session, series: series),
      ),
    );
    if (saved == true && mounted) {
      setState(() => _generation++);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListScreen<ManagedSeries>(
      key: ValueKey(_generation),
      title: context.t('manage.series'),
      emptyKey: 'manage.series_empty',
      reloadKey: 'manage.reload',
      load: () => widget.session.authorized(
        (api, token) => ManageApi(api).allSeries(token),
      ),
      builder: (context, series) => ListView(
        children: [
          for (final one in series)
            ListTile(
              title: Text(one.name),
              subtitle: Text(
                context.plural('browse.book_count', one.bookCount),
              ),
              trailing: one.libraryIds.isEmpty
                  ? Text(context.t('manage.no_library'))
                  : const Icon(Icons.chevron_right),
              onTap: () => _open(one),
            ),
        ],
      ),
    );
  }
}
