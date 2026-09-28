import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/tournament_manager.dart';
import 'package:rise_together_game/src/levels/custom_level.dart';
import 'package:rise_together_game/src/levels/level_library.dart';
import 'package:rise_together_game/src/levels/solo_progress.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_helpers.dart';

CustomLevel _level(String name) => CustomLevel.create(
  heightMultiplier: 2,
  name: name,
  objects: [
    CustomObject.create(
      type: CustomObjectType.fatal,
      x: 0,
      y: 10,
      levelHeight: 20,
    )!,
  ],
)!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(silenceLogs);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.initialize();
    final settings = Settings.instance.appSettings;
    await settings.setInt('player.max_completed_level', -1);
    await settings.setInt('player.best_solo_level', 0);
    await settings.setString('player.best_times', '{}');
    await settings.setString('levels.library', '');
  });

  group('SoloProgress', () {
    test(
      'level 1 is always startable, and finishing unlocks the next',
      () async {
        final progress = SoloProgress();
        expect(progress.startableLevelCount, 1);
        await progress.recordCompleted(0);
        expect(progress.startableLevelCount, 2);
        await progress.recordCompleted(4);
        await progress.recordCompleted(2); // never goes backwards
        expect(progress.maxCompletedLevel, 4);
        expect(progress.startableLevelCount, 6);
        await progress.recordCompleted(99);
        expect(progress.startableLevelCount, SoloProgress.builtInLevelCount);
      },
    );

    test('an older best score unlocks the levels below it', () async {
      await Settings.instance.appSettings.setInt('player.best_solo_level', 3);
      expect(SoloProgress().maxCompletedLevel, 2);
    });

    test('keeps only the best time, and survives corrupt storage', () async {
      final progress = SoloProgress();
      final key = SoloProgress.builtInRunKey(0);
      expect(await progress.recordTime(key, 100), isTrue);
      expect(await progress.recordTime(key, 120), isFalse);
      expect(await progress.recordTime(key, 90), isTrue);
      expect(progress.bestTime(key), 90);

      await Settings.instance.appSettings.setString(
        'player.best_times',
        '{oops',
      );
      expect(progress.bestTime(key), isNull);
      await Settings.instance.appSettings.setString(
        'player.best_times',
        jsonEncode({key: 'fast', 'other': -1}),
      );
      expect(progress.bestTime(key), isNull);
      expect(progress.bestTime('other'), isNull);
    });
  });

  test('a run can start part-way up', () {
    final manager = TournamentManager()
      ..startIndividualCondition(durationSeconds: null);
    manager.setTeamLevelIndex(0, 3);
    expect(manager.getTeamLevelIndex(0), 3);
    expect(manager.individualConditionDuration, isNull);
  });

  group('LevelLibrary', () {
    test('persists levels and packs', () async {
      final library = LevelLibrary();
      final a = library.add(_level('A'))!;
      final b = library.add(_level('B'))!;
      expect(library.savePack(name: 'Both', levelIds: [b, a]), isTrue);
      await library.flush();

      final reloaded = LevelLibrary();
      expect(reloaded.levels.map((l) => l.level.name), ['A', 'B']);
      final pack = reloaded.packs.single;
      expect(pack.name, 'Both');
      expect(reloaded.levelsOf(pack).map((l) => l.name), ['B', 'A']);
      expect(reloaded.selections.first.key, 'pack:${pack.id}');
    });

    test('deleting a level removes it from packs', () {
      final library = LevelLibrary();
      final a = library.add(_level('A'))!;
      final b = library.add(_level('B'))!;
      library.savePack(name: 'P', levelIds: [a, b]);
      library.remove(a);
      expect(library.packs.single.levelIds, [b]);
    });

    test('is capped', () {
      final library = LevelLibrary();
      final added = library.addAll(
        List.generate(
          CustomLevelLimits.maxLevelsPerFile + 5,
          (i) => _level('$i'),
        ),
      );
      expect(added, CustomLevelLimits.maxLevelsPerFile);
      expect(library.add(_level('extra')), isNull);
    });

    test('drops corrupt or hostile stored data instead of crashing', () {
      for (final stored in [
        '{',
        '[]',
        jsonEncode({'version': 2, 'levels': []}),
        jsonEncode({
          'version': 1,
          'levels': [
            {'id': '../x', 'height': 2},
            {'id': 'ok', 'height': 'tall'},
            {'id': 'good', 'height': 2, 'name': 'Kept'},
            {'id': 'good', 'height': 3},
          ],
          'packs': [
            {'id': 'p', 'name': 7, 'levels': []},
            {
              'id': 'q',
              'name': 'Pack',
              'levels': ['good', 'missing', 5],
            },
          ],
        }),
      ]) {
        final library = LevelLibrary(stored: stored);
        if (stored.contains('Kept')) {
          expect(library.levels.map((l) => l.level.name), ['Kept']);
          expect(library.packs.single.levelIds, ['good']);
        } else {
          expect(library.levels, isEmpty);
        }
      }
    });
  });
}
