import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/game_geometry.dart';
import 'package:rise_together_game/src/game/level_sequence.dart';
import 'package:rise_together_game/src/levels/custom_level.dart';

CustomObject _obj(
  CustomObjectType type,
  double x,
  double y, {
  double? param,
  double height = 50,
}) => CustomObject.create(
  type: type,
  x: x,
  y: y,
  param: param,
  levelHeight: height,
)!;

CustomLevel _level() => CustomLevel.create(
  heightMultiplier: 5,
  name: 'Tricky one',
  objects: [
    _obj(CustomObjectType.fatal, -2, 10),
    _obj(CustomObjectType.powerupWidth, 1.25, 20, param: 1.3),
    _obj(CustomObjectType.powerdownWidth, 0, 25, param: 0.7),
    _obj(CustomObjectType.controlReversal, 4.5, 30, param: 10),
    _obj(CustomObjectType.controlReversalZone, 0, 40, param: 4),
  ],
)!;

/// A valid wire pack with one level holding [object], for mutation tests.
String _wireWith(Object? object, {Object? height = 5}) => jsonEncode([
  1,
  [
    [
      height,
      [object],
    ],
  ],
]);

void main() {
  test('limits agree with the game geometry', () {
    expect(CustomLevelLimits.levelWidth, GameGeometry.levelWidth);
    expect(
      CustomLevelLimits.spawnClearance,
      greaterThan(-GameGeometry.ballSpawnY + GameGeometry.ballRadius),
    );
  });

  group('wire', () {
    test('round-trips', () {
      final pack = CustomLevelPack.create([_level(), _level()])!;
      final decoded = CustomLevelPack.fromWire(pack.toWire())!;
      expect(decoded.levels, hasLength(2));
      expect(decoded.levels.first.sameLayout(_level()), isTrue);
    });

    test('carries no names', () {
      final wire = CustomLevelPack.create([_level()])!.toWire();
      expect(wire, isNot(contains('Tricky')));
      expect(CustomLevelPack.fromWire(wire)!.levels.single.name, isEmpty);
    });

    test('the largest valid pack fits the size limit', () {
      final level = CustomLevel.create(
        heightMultiplier: 19.99,
        objects: [
          for (var i = 0; i < CustomLevelLimits.maxObjects; i++)
            _obj(
              CustomObjectType.powerdownWidth,
              -4.49,
              100 + i * 2.37,
              param: 0.93,
              height: 199.9,
            ),
        ],
      )!;
      final pack = CustomLevelPack.create(
        List.filled(CustomLevelLimits.maxLevelsPerPack, level),
      )!;
      final wire = pack.toWire();
      expect(wire.length, lessThan(CustomLevelLimits.maxWireChars));
      expect(CustomLevelPack.fromWire(wire), isNotNull);
    });

    test('accepts an int where a double was sent', () {
      expect(CustomLevelPack.fromWire(_wireWith([0, 1, 10])), isNotNull);
    });

    final rejected = <String, Object?>{
      'null': null,
      'a number': 5,
      'a map': <String, Object>{},
      'not JSON': '[1, [',
      'too long': ' ' * (CustomLevelLimits.maxWireChars + 1),
      'wrong version': jsonEncode([2, []]),
      'no levels': jsonEncode([1, []]),
      'extra top-level element': jsonEncode([1, [], 3]),
      'too many levels': jsonEncode([
        1,
        List.filled(CustomLevelLimits.maxLevelsPerPack + 1, [5, []]),
      ]),
      'too many objects': jsonEncode([
        1,
        [
          [
            20,
            List.filled(CustomLevelLimits.maxObjects + 1, [0, 0, 10]),
          ],
        ],
      ]),
      'height too small': _wireWith([0, 0, 5], height: 0.5),
      'height too big': _wireWith([0, 0, 5], height: 21),
      'height as string': _wireWith([0, 0, 5], height: '5'),
      'height NaN-ish': '[1,[[1e999,[]]]]',
      'unknown object type': _wireWith([99, 0, 10]),
      'negative object type': _wireWith([-1, 0, 10]),
      'double object type': _wireWith([0.0, 0, 10]),
      'object as a map': _wireWith({'t': 0}),
      'object too short': _wireWith([0, 0]),
      'object too long': _wireWith([1, 0, 10, 1.3, 1]),
      'param on a fatal': _wireWith([0, 0, 10, 1]),
      'missing param': _wireWith([1, 0, 10]),
      'param out of range': _wireWith([1, 0, 10, 5]),
      'param as string': _wireWith([1, 0, 10, '1.3']),
      'x off the level': _wireWith([0, 4.6, 10]),
      'y in the spawn area': _wireWith([0, 0, 1]),
      'y above the level': _wireWith([0, 0, 49.9]),
      'zone off centre': _wireWith([4, 1, 10, 4]),
      'nested junk': _wireWith([
        0,
        [0],
        10,
      ]),
      'deep nesting': '${'[' * 5000}${']' * 5000}',
    };
    rejected.forEach((name, wire) {
      test('rejects $name', () {
        expect(CustomLevelPack.fromWire(wire), isNull);
      });
    });
  });

  group('file', () {
    test('round-trips, names included', () {
      final text = CustomLevelFile.encode([_level()]);
      final decoded = CustomLevelFile.decode(text)!;
      expect(decoded.single.name, 'Tricky one');
      expect(decoded.single.sameLayout(_level()), isTrue);
    });

    test('a missing parameter takes the default', () {
      final text = jsonEncode({
        'format': CustomLevelFile.format,
        'version': 1,
        'levels': [
          {
            'height': 3,
            'objects': [
              {'type': 'powerupWidth', 'x': 0, 'y': 5},
            ],
          },
        ],
      });
      final level = CustomLevelFile.decode(text)!.single;
      expect(level.objects.single.param, 1.3);
    });

    test('strips control and bidi characters from names', () {
      expect(CustomLevel.sanitizeName('  a\u202Eb\u0000c\n  '), 'abc');
      expect(
        CustomLevel.sanitizeName('x' * 100).length,
        CustomLevelLimits.maxNameLength,
      );
    });

    Map<String, Object?> file(Object? level) => {
      'format': CustomLevelFile.format,
      'version': 1,
      'levels': [level],
    };
    final rejected = <String, String>{
      'not JSON': '{',
      'a list': '[]',
      'wrong format': jsonEncode({
        ...file({'height': 2}),
        'format': 'x',
      }),
      'wrong version': jsonEncode({
        ...file({'height': 2}),
        'version': 2,
      }),
      'no levels': jsonEncode({...file(null), 'levels': []}),
      'bad level': jsonEncode(file({'height': 'tall'})),
      'unknown type': jsonEncode(
        file({
          'height': 2,
          'objects': [
            {'type': 'bomb', 'x': 0, 'y': 5},
          ],
        }),
      ),
      'bad param': jsonEncode(
        file({
          'height': 2,
          'objects': [
            {'type': 'controlReversal', 'x': 0, 'y': 5, 'duration': 'long'},
          ],
        }),
      ),
      'name not a string': jsonEncode(file({'height': 2, 'name': 3})),
      'too big': ' ' * (CustomLevelLimits.maxFileChars + 1),
    };
    rejected.forEach((name, text) {
      test('rejects $name', () {
        expect(CustomLevelFile.decode(text), isNull);
      });
    });
  });

  group('editing', () {
    test('clampPosition always gives a valid position', () {
      for (final type in CustomObjectType.values) {
        final param = type.param?.fallback;
        for (final (x, y) in [(-100.0, -100.0), (100.0, 1e6), (0.333, 7.777)]) {
          final (cx, cy) = CustomObject.clampPosition(type, param, x, y, 30);
          expect(
            CustomObject.create(
              type: type,
              x: cx,
              y: cy,
              param: param,
              levelHeight: 30,
            ),
            isNotNull,
            reason: '$type at ($x, $y)',
          );
        }
      }
    });

    test('shrinking a level below an object is refused', () {
      expect(_level().copyWith(heightMultiplier: 2), isNull);
    });
  });

  test('custom sequences build fixed placements', () {
    final sequence = LevelSequence.custom([_level()]);
    expect(sequence.isCustom, isTrue);
    final level = sequence.getLevelAt(0);
    expect(level.verticalHeight, 50);
    final a = level.spawnConfigForSeed(1)!.computePlacements(1.7);
    final b = level.spawnConfigForSeed(999)!.computePlacements(0.5);
    expect(a.map((p) => p.position), b.map((p) => p.position));
    expect(a.first.position.x, -2);
    expect(a.first.position.y, -10);
    expect(a.last.size.y, 4);
  });
}
