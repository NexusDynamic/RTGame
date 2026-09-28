import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/level_sequence.dart';
import 'package:rise_together_game/src/game/rise_together_levels.dart';

/// The configured default; placement clamps x against the paddle's reach.
const _paddleWidthMultiplier = 1.7;

void main() {
  group('Levels 1-4 are unchanged', () {
    // Captured when Level 5+ moved to LevelSpawnConfig.slotted. These levels
    // were used for the validation groups and must keep placing identically.
    const golden = <String, List<(double, double)>>{
      'Level2 0': [(0.0, -8.40455436706543)],
      'Level2 12345': [(0.0, -9.04245376586914)],
      'Level3 0': [
        (0.42156848311424255, -6.5230631828308105),
        (0.0, -17.537242889404297),
      ],
      'Level3 12345': [
        (0.38336753845214844, -7.169942855834961),
        (0.0, -22.92658233642578),
      ],
      'Level4 0': [
        (1.157111406326294, -10.055155754089355),
        (-0.01498274877667427, -27.286226272583008),
        (0.0, -46.95985794067383),
      ],
      'Level4 12345': [
        (-1.0429432392120361, -10.71882438659668),
        (1.493943452835083, -27.058177947998047),
        (0.0, -43.80632400512695),
      ],
    };

    test('Level 1 has no objects', () {
      expect(const Level1().spawnConfigForSeed(0), isNull);
    });

    for (final level in const [Level2(), Level3(), Level4()]) {
      for (final seed in [0, 12345]) {
        test('${level.runtimeType} seed $seed', () {
          final placements = level
              .spawnConfigForSeed(seed)!
              .computePlacements(_paddleWidthMultiplier);
          final expected = golden['${level.runtimeType} $seed']!;
          expect(placements, hasLength(expected.length));
          for (var i = 0; i < expected.length; i++) {
            expect(placements[i].position.x, closeTo(expected[i].$1, 1e-9));
            expect(placements[i].position.y, closeTo(expected[i].$2, 1e-9));
          }
        });
      }
    }
  });

  group('Levels 5+', () {
    final sequence = LevelSequence.defaultSequence();
    final levels = [
      for (var i = 4; i < sequence.levelCount; i++) sequence.getLevelAt(i),
    ];

    test('the sequence has 10 levels', () {
      expect(sequence.levelCount, 10);
    });

    test('object count never decreases', () {
      var previous = 0;
      for (final level in levels) {
        final count = level.spawnConfigForSeed(0)!.spawns.length;
        expect(count, greaterThanOrEqualTo(previous), reason: '$level');
        previous = count;
      }
    });

    for (final level in levels) {
      test('${level.runtimeType}: no vertical overlap, inside the level', () {
        for (var seed = 0; seed <= 500; seed++) {
          final placements = level
              .spawnConfigForSeed(seed)!
              .computePlacements(_paddleWidthMultiplier);
          // y is negative-up; sort bottom to top.
          final extents = [
            for (final p in placements)
              (p.position.y + p.size.y / 2, p.position.y - p.size.y / 2),
          ]..sort((a, b) => b.$1.compareTo(a.$1));

          for (final (bottom, top) in extents) {
            expect(bottom, lessThanOrEqualTo(0.0), reason: 'seed $seed');
            expect(
              top,
              greaterThanOrEqualTo(-level.verticalHeight),
              reason: 'seed $seed',
            );
          }
          for (var i = 1; i < extents.length; i++) {
            // The next object's bottom must be above this one's top.
            expect(
              extents[i].$1,
              lessThan(extents[i - 1].$2),
              reason: '${level.runtimeType} seed $seed, objects ${i - 1}/$i',
            );
          }
        }
      });
    }
  });
}
