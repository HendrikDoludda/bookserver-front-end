import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:material_ui/material_ui.dart';

/// The reader bar's button for the mode a book is read in: its icon shows [mode], its menu offers
/// all three. A choice shows at once through [onChanged], then is saved as the user's mode for
/// the series [seriesId]; a book outside any series saves it nowhere.
class ReadingModeButton extends StatelessWidget {
  const ReadingModeButton({
    super.key,
    required this.session,
    required this.seriesId,
    required this.mode,
    required this.onChanged,
  });

  final SessionController session;
  final int? seriesId;
  final ReadingMode mode;
  final ValueChanged<ReadingMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ReadingMode>(
      icon: Icon(_icon(mode)),
      tooltip: context.t('reader.mode'),
      onSelected: (chosen) => _choose(context, chosen),
      itemBuilder: (context) => [
        for (final each in ReadingMode.values)
          CheckedPopupMenuItem(
            value: each,
            checked: each == mode,
            child: Text(context.t(_label(each))),
          ),
      ],
    );
  }

  // The mode on screen is saved too: a book may show the direction its file states, and choosing
  // it makes it the mode of every book of the series.
  Future<void> _choose(BuildContext context, ReadingMode chosen) async {
    onChanged(chosen);
    final seriesId = this.seriesId;
    if (seriesId == null) {
      return;
    }
    // Taken now: the reader may be closed by the time the save fails.
    final messenger = ScaffoldMessenger.of(context);
    final notSaved = context.t('reader.mode_not_saved');
    try {
      await session.authorized(
        (api, sessionToken) =>
            BrowseApi(api).setReadingMode(seriesId, chosen, sessionToken),
      );
    } on Exception {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(notSaved)));
    }
  }
}

// Arrows that point the way the next page lies on screen; unlike `arrow_back`, these don't turn
// around in a language written right to left.
IconData _icon(ReadingMode mode) => switch (mode) {
  ReadingMode.rtl => Icons.west,
  ReadingMode.ltr => Icons.east,
  ReadingMode.continuous => Icons.south,
};

String _label(ReadingMode mode) => switch (mode) {
  ReadingMode.rtl => 'reader.mode_rtl',
  ReadingMode.ltr => 'reader.mode_ltr',
  ReadingMode.continuous => 'reader.mode_continuous',
};
