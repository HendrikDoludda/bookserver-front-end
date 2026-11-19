import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

/// The layout of a screen that is one form: centred, no wider than [Widths.form], and
/// scrollable when the keyboard leaves little room. A form pushed onto another screen gets a top
/// bar with Back, unless [back] is false.
class FormPage extends StatelessWidget {
  const FormPage({super.key, required this.children, this.back = true});

  final List<Widget> children;
  final bool back;

  @override
  Widget build(BuildContext context) {
    final pushed = ModalRoute.of(context)?.canPop ?? false;
    return Scaffold(
      appBar: pushed && back ? AppBar() : null,
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
