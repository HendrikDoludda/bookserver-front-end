import 'dart:io';

import 'package:bookserver/data/preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_preferences_store.dart';

void main() {
  group('Preferences', () {
    test('are right-handed until told otherwise', () {
      expect(const Preferences().handedness, Handedness.right);
    });

    test('read back what they wrote', () {
      for (final handedness in Handedness.values) {
        final preferences = Preferences(handedness: handedness);
        expect(Preferences.fromJson(preferences.toJson()), preferences);
      }
    });

    test('read a value they do not know, or none, as the default', () {
      for (final json in [
        {'handedness': 'both'},
        {'handedness': 1},
        <String, Object?>{},
      ]) {
        expect(
          Preferences.fromJson(json).handedness,
          Handedness.right,
          reason: '$json',
        );
      }
    });

    test('refuse JSON that is no object', () {
      for (final json in [<Object?>[], 'left', null]) {
        expect(
          () => Preferences.fromJson(json),
          throwsFormatException,
          reason: '$json',
        );
      }
    });
  });

  group('FilePreferencesStore', () {
    late Directory folder;
    setUp(() async {
      folder = await Directory.systemTemp.createTemp('preferences_test');
    });
    tearDown(() => folder.delete(recursive: true));

    FilePreferencesStore store() =>
        FilePreferencesStore(folder: () async => folder);

    test(
      'keeps the preferences in preferences.json and reads them back',
      () async {
        await store().write(const Preferences(handedness: Handedness.left));

        expect(
          await store().read(),
          const Preferences(handedness: Handedness.left),
        );
        expect(File('${folder.path}/preferences.json').existsSync(), isTrue);
      },
    );

    test('nothing kept reads as none', () async {
      expect(await store().read(), isNull);
    });

    test('a broken file reads as none and is deleted', () async {
      final kept = File('${folder.path}/preferences.json');
      await kept.writeAsString('[]');

      expect(await store().read(), isNull);
      expect(kept.existsSync(), isFalse);
    });
  });

  group('PreferencesController', () {
    test('starts right-handed when nothing is kept', () async {
      final controller = PreferencesController(store: MemoryPreferencesStore());
      var notified = 0;
      controller.addListener(() => notified++);

      await controller.load();

      expect(controller.preferences.handedness, Handedness.right);
      expect(notified, 0);
    });

    test('starts with what a launch before kept', () async {
      final store = MemoryPreferencesStore();
      await PreferencesController(store: store).setHandedness(Handedness.left);

      final nextLaunch = PreferencesController(store: store);
      await nextLaunch.load();

      expect(nextLaunch.preferences.handedness, Handedness.left);
    });

    test('a change shows at once and is kept', () async {
      final store = MemoryPreferencesStore();
      final controller = PreferencesController(store: store);
      var notified = 0;
      controller.addListener(() => notified++);

      await controller.setHandedness(Handedness.left);

      expect(controller.preferences.handedness, Handedness.left);
      expect(notified, 1);
      expect(store.preferences?.handedness, Handedness.left);
    });

    test('choosing what is already chosen changes and keeps nothing', () async {
      final store = MemoryPreferencesStore();
      final controller = PreferencesController(store: store);
      var notified = 0;
      controller.addListener(() => notified++);

      await controller.setHandedness(Handedness.right);

      expect(notified, 0);
      expect(store.preferences, isNull);
    });

    test(
      'a change that cannot be kept still holds while the app runs',
      () async {
        final controller = PreferencesController(store: _FullDisk());

        await controller.setHandedness(Handedness.left);

        expect(controller.preferences.handedness, Handedness.left);
      },
    );
  });
}

/// A store whose every write fails, as on a full disk.
class _FullDisk implements PreferencesStore {
  @override
  Future<Preferences?> read() async => null;

  @override
  Future<void> write(Preferences preferences) async =>
      throw const FileSystemException('No space left on device');
}
