import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

/// One row of a book's contents: its title, how deep it lies, and what choosing it does — null for
/// a row that goes nowhere, which shows but can't be chosen.
typedef ContentsRow = ({String title, int depth, VoidCallback? go});

/// The rows of a tree of contents [entries], each entry followed by the ones beneath it, one
/// level deeper; [titleOf], [childrenOf] and [goOf] read an entry.
List<ContentsRow> contentsRows<T>(
  List<T> entries, {
  required String Function(T entry) titleOf,
  required List<T> Function(T entry) childrenOf,
  required VoidCallback? Function(T entry) goOf,
  int depth = 0,
}) => [
  for (final entry in entries) ...[
    (title: titleOf(entry), depth: depth, go: goOf(entry)),
    ...contentsRows(
      childrenOf(entry),
      titleOf: titleOf,
      childrenOf: childrenOf,
      goOf: goOf,
      depth: depth + 1,
    ),
  ],
];

/// The reader bar's contents button: it opens [rows] in a sheet, indented by depth, and choosing
/// one closes the sheet and goes there.
class ContentsButton extends StatelessWidget {
  const ContentsButton({super.key, required this.rows});

  final List<ContentsRow> rows;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.toc),
      tooltip: context.t('reader.contents'),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => _Contents(rows: rows),
      ),
    );
  }
}

class _Contents extends StatelessWidget {
  const _Contents({required this.rows});

  final List<ContentsRow> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.medium),
          child: Text(
            context.t('reader.contents'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              final go = row.go;
              return ListTile(
                contentPadding: EdgeInsetsDirectional.only(
                  start: Spacing.medium + row.depth * Spacing.large,
                  end: Spacing.medium,
                ),
                title: Text(row.title),
                enabled: go != null,
                onTap: go == null
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        go();
                      },
              );
            },
          ),
        ),
      ],
    );
  }
}
