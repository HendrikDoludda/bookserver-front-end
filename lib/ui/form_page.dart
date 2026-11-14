import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

/// The layout of a screen that is one form: centred, no wider than [Widths.form], and
/// scrollable when the keyboard leaves little room.
class FormPage extends StatelessWidget {
  const FormPage({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.large),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Widths.form),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Spacing.medium,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
