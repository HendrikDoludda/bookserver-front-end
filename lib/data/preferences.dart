import 'dart:io';

import 'package:bookserver/data/json_file.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The hand that holds the device: the reader's buttons gather on its side.
enum Handedness { left, right }

/// What this device keeps for whoever uses it — outside the session record, so it outlasts
/// signing out and changing servers.
@immutable
class Preferences {
  const Preferences({this.handedness = Handedness.right});

  /// Reads what [toJson] wrote; a value it doesn't know is the default.
  factory Preferences.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('Not preferences.');
    }
    return Preferences(
      handedness: switch (json['handedness']) {
        'left' => Handedness.left,
        _ => Handedness.right,
      },
    );
  }

  final Handedness handedness;

  Preferences copyWith({Handedness? handedness}) =>
      Preferences(handedness: handedness ?? this.handedness);

  Map<String, Object?> toJson() => {'handedness': handedness.name};

  @override
  bool operator ==(Object other) =>
      other is Preferences && other.handedness == handedness;

  @override
  int get hashCode => handedness.hashCode;
}

/// Where the app keeps its [Preferences] between launches.
abstract interface class PreferencesStore {
  Future<Preferences?> read();

  Future<void> write(Preferences preferences);
}

/// Keeps the preferences as `preferences.json` in the app's support folder.
class FilePreferencesStore implements PreferencesStore {
  FilePreferencesStore({
    Future<Directory> Function() folder = getApplicationSupportDirectory,
  }) : _file = JsonFile('preferences.json', folder: folder);

  final JsonFile _file;

  /// The kept preferences; an unreadable file is deleted and counts as none.
  @override
  Future<Preferences?> read() => _file.read(Preferences.fromJson);

  @override
  Future<void> write(Preferences preferences) =>
      _file.write(preferences.toJson());
}

/// The device's [Preferences], changed at once and kept by its [PreferencesStore].
class PreferencesController extends ChangeNotifier {
  PreferencesController({required this._store});

  final PreferencesStore _store;
  var _preferences = const Preferences();

  Preferences get preferences => _preferences;

  /// Reads the kept preferences; without any, the defaults stay.
  Future<void> load() async {
    final kept = await _store.read();
    if (kept != null && kept != _preferences) {
      _preferences = kept;
      notifyListeners();
    }
  }

  Future<void> setHandedness(Handedness handedness) =>
      _change(_preferences.copyWith(handedness: handedness));

  Future<void> _change(Preferences preferences) async {
    if (preferences == _preferences) {
      return;
    }
    _preferences = preferences;
    notifyListeners();
    try {
      await _store.write(preferences);
    } on FileSystemException {
      // The change holds while the app runs; the next launch starts from what was kept before.
    }
  }
}
