import 'package:bookserver/data/preferences.dart';
import 'package:material_ui/material_ui.dart';

/// The app's [PreferencesController] for the widgets below: they read its preferences, rebuild
/// when they change, and change them.
class PreferencesScope extends InheritedNotifier<PreferencesController> {
  const PreferencesScope({
    super.key,
    required PreferencesController controller,
    required super.child,
  }) : super(notifier: controller);

  static PreferencesController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<PreferencesScope>();
    if (scope == null) {
      throw FlutterError('No PreferencesScope above this widget.');
    }
    return scope.notifier!;
  }
}
