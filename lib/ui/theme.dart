import 'package:material_ui/material_ui.dart';

/// The spacing scale: the gaps between and around widgets.
abstract final class Spacing {
  static const double small = 8;
  static const double medium = 16;
  static const double large = 24;
}

// Kept from the Flutter template until branding (08) sets the app's colours.
const Color _seed = Colors.deepPurple;

final ThemeData lightTheme = ThemeData(
  colorScheme: .fromSeed(seedColor: _seed),
);

final ThemeData darkTheme = ThemeData(
  colorScheme: .fromSeed(seedColor: _seed, brightness: .dark),
);
