import 'package:bookserver/data/preferences.dart';

/// Keeps the preferences in memory, where a test can set and read them.
class MemoryPreferencesStore implements PreferencesStore {
  Preferences? preferences;

  @override
  Future<Preferences?> read() async => preferences;

  @override
  Future<void> write(Preferences preferences) async =>
      this.preferences = preferences;
}
