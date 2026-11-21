import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/cover.dart';
import 'package:bookserver/ui/cover_grid.dart';
import 'package:bookserver/ui/list_screen.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

// Material's opacity for what can't be used.
const _unavailableOpacity = 0.38;

/// What a form does with a series' or a library's cover once it is saved.
sealed class CoverChoice {
  const CoverChoice();
}

/// Back to the cover the server picks: a series' first book's, a library's first series'.
final class AutomaticCover extends CoverChoice {
  const AutomaticCover();
}

/// The cover of [id] — a book for a series, a series for a library — named [name].
final class PickedCover extends CoverChoice {
  const PickedCover(this.id, this.name);

  final int id;
  final String name;
}

/// The covers a series or a library can show, Automatic first; a tap closes the screen with that
/// [CoverChoice]. A candidate whose cover doesn't load can't be picked: the server refuses one
/// without a cover.
class CoverChoiceScreen<T extends Object> extends StatelessWidget {
  const CoverChoiceScreen({
    super.key,
    required this.session,
    required this.kind,
    required this.load,
    required this.idOf,
    required this.nameOf,
  });

  final SessionController session;

  /// What the candidates are: [CoverKind.book] for a series' cover, [CoverKind.series] for a
  /// library's.
  final CoverKind kind;

  /// Loads the candidates, in the order they show.
  final Future<List<T>> Function() load;

  final int Function(T candidate) idOf;
  final String Function(BuildContext context, T candidate) nameOf;

  @override
  Widget build(BuildContext context) {
    return ListScreen<T?>(
      title: context.t('manage.choose_cover'),
      // Automatic, as null, is always there, so the empty text never shows.
      load: () async => [null, ...await load()],
      emptyKey: kind == CoverKind.book
          ? 'browse.books_empty'
          : 'manage.series_empty',
      reloadKey: 'manage.reload',
      builder: (context, choices) => CoverGrid(
        itemCount: choices.length,
        itemBuilder: (context, index) => switch (choices[index]) {
          null => CoverCard(
            cover: const _AutomaticPicture(),
            name: context.t('manage.cover_automatic'),
            onTap: () => Navigator.of(context).pop(const AutomaticCover()),
          ),
          final candidate => _CandidateCard(
            session: session,
            kind: kind,
            choice: PickedCover(idOf(candidate), nameOf(context, candidate)),
          ),
        },
      ),
    );
  }
}

/// A form's Cover row: the cover on show — or, once one is picked, the one saving puts there —
/// and a tap that opens [CoverChoiceScreen].
class CoverField extends StatelessWidget {
  const CoverField({
    super.key,
    required this.session,
    required this.current,
    required this.candidates,
    required this.choice,
    required this.onTap,
  });

  final SessionController session;

  /// The cover on show now; null for a library not created yet.
  final ({CoverKind kind, int id})? current;

  /// What a [PickedCover]'s id names: books for a series, series for a library.
  final CoverKind candidates;

  /// What saving does with the cover; null leaves it as it is.
  final CoverChoice? choice;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final current = this.current;
    final picture = switch (choice) {
      PickedCover(:final id) => Cover(
        session: session,
        kind: candidates,
        id: id,
      ),
      AutomaticCover() => const _AutomaticPicture(),
      null when current != null => Cover(
        session: session,
        kind: current.kind,
        id: current.id,
      ),
      null => const _AutomaticPicture(),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(width: Covers.thumbnailWidth, child: picture),
      title: Text(context.t('manage.cover')),
      subtitle: switch (choice) {
        PickedCover(:final name) => Text(name),
        AutomaticCover() => Text(context.t('manage.cover_automatic')),
        null => null,
      },
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// A candidate's cover and name, picked with a tap — but not while its cover can't be shown.
class _CandidateCard extends StatefulWidget {
  const _CandidateCard({
    required this.session,
    required this.kind,
    required this.choice,
  });

  final SessionController session;
  final CoverKind kind;
  final PickedCover choice;

  @override
  State<_CandidateCard> createState() => _CandidateCardState();
}

class _CandidateCardState extends State<_CandidateCard> {
  late final ImageStream _stream;
  late final _listener = ImageStreamListener(
    (_, _) {},
    onError: (_, _) {
      if (mounted) {
        setState(() => _missing = true);
      }
    },
  );
  var _missing = false;

  @override
  void initState() {
    super.initState();
    // The image the card's Cover shows, under the same cache key: this asks the server nothing
    // more.
    _stream = Cover.imageOf(
      widget.session,
      widget.kind,
      widget.choice.id,
    ).resolve(ImageConfiguration.empty)..addListener(_listener);
  }

  @override
  void dispose() {
    _stream.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _missing ? _unavailableOpacity : 1,
      child: CoverCard(
        cover: Cover(
          session: widget.session,
          kind: widget.kind,
          id: widget.choice.id,
        ),
        name: widget.choice.name,
        onTap: _missing ? null : () => Navigator.of(context).pop(widget.choice),
      ),
    );
  }
}

/// Automatic's picture: a cover's shape, with a sign that the server picks what shows.
class _AutomaticPicture extends StatelessWidget {
  const _AutomaticPicture();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: Covers.aspectRatio,
      child: ColoredBox(
        color: colors.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.auto_awesome_outlined,
            color: colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
