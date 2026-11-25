import 'package:bookserver/data/manage_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/list_screen.dart';
import 'package:bookserver/ui/manage/manage_series_screen.dart';
import 'package:material_ui/material_ui.dart';

/// Every series but [except], to pick the one it is merged into; a tap closes the screen with
/// that series.
class SeriesChoiceScreen extends StatelessWidget {
  const SeriesChoiceScreen({
    super.key,
    required this.session,
    required this.except,
  });

  final SessionController session;
  final int except;

  @override
  Widget build(BuildContext context) {
    return ListScreen<ManagedSeries>(
      title: context.t('manage.choose_merge_target'),
      emptyKey: 'manage.no_merge_target',
      reloadKey: 'manage.reload',
      load: () async {
        final series = await session.authorized(
          (api, token) => ManageApi(api).allSeries(token),
        );
        return [
          for (final one in series)
            if (one.id != except) one,
        ];
      },
      builder: (context, series) => ListView(
        children: [
          for (final one in series)
            SeriesTile(
              series: one,
              onTap: () => Navigator.of(context).pop(one),
            ),
        ],
      ),
    );
  }
}
