import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

/// A message in the middle of the space it gets, with an optional button under it.
class Notice extends StatelessWidget {
  const Notice({super.key, required this.text, this.color, this.action});

  final String text;
  final Color? color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.large),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: Spacing.medium,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: color),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}
