import 'package:material_ui/material_ui.dart';

/// The spacing scale: the gaps between and around widgets.
abstract final class Spacing {
  static const double small = 8;
  static const double medium = 16;
  static const double large = 24;
}

/// The widest a block of content gets, so it stays readable on a wide window.
abstract final class Widths {
  static const double form = 400;

  /// The widest a column of running text gets, so its lines stay easy to follow.
  static const double reading = 720;
}

/// The book, series and library covers of the browse grids.
abstract final class Covers {
  /// Width over height, the shape of most book covers.
  static const double aspectRatio = 2 / 3;

  /// The widest a cover's tile gets.
  static const double maxTileWidth = 180;

  // Sharp at the widest tile on a 3× phone screen; a full-size cover would decode to megabytes.
  static final int decodeWidth = (maxTileWidth * 3).ceil();
}

// Kept from the Flutter template until branding (08) sets the app's colours.
const Color _seed = Colors.deepPurple;

final ThemeData lightTheme = ThemeData(
  colorScheme: .fromSeed(seedColor: _seed),
);

final ThemeData darkTheme = ThemeData(
  colorScheme: .fromSeed(seedColor: _seed, brightness: .dark),
);
