import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:rise_together_game/src/levels/custom_level.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';

/// A level in the library, with a local id so packs can refer to it.
@immutable
class LibraryLevel {
  const LibraryLevel(this.id, this.level);

  final String id;
  final CustomLevel level;
}

/// An ordered set of the player's levels, played one after another.
@immutable
class LibraryPack {
  LibraryPack(this.id, String name, List<String> levelIds)
    : name = CustomLevel.sanitizeName(name),
      levelIds = List.unmodifiable(levelIds);

  final String id;
  final String name;
  final List<String> levelIds;
}

/// Custom levels to play: a pack, or a single level.
@immutable
class CustomSelection {
  const CustomSelection({
    required this.key,
    required this.name,
    required this.levels,
  });

  /// Stable id for best times: `pack:<id>` or `level:<id>`.
  final String key;
  final String name;
  final List<CustomLevel> levels;

  CustomLevelPack? get pack => CustomLevelPack.create(levels);
}

/// The player's own levels and packs, stored on this device only.
///
/// Stored as JSON in the `levels.library` setting and re-validated on every
/// load; anything invalid is dropped rather than trusted. Only the editor and
/// imports the player chose write here: levels received online are never
/// added.
class LevelLibrary extends ChangeNotifier with AppSettings {
  LevelLibrary({String? stored}) {
    _load(stored ?? appSettings.getString(_key));
  }

  static const _key = 'levels.library';
  static const _version = 1;
  static const maxPacks = 20;
  static final _idPattern = RegExp(r'^[a-z0-9]{1,24}$');

  final List<LibraryLevel> _levels = [];
  final List<LibraryPack> _packs = [];

  List<LibraryLevel> get levels => List.unmodifiable(_levels);
  List<LibraryPack> get packs => List.unmodifiable(_packs);

  bool get isFull => _levels.length >= CustomLevelLimits.maxLevelsPerFile;

  LibraryLevel? levelById(String id) =>
      _levels.where((l) => l.id == id).firstOrNull;

  /// The levels of [pack] that still exist, in order.
  List<CustomLevel> levelsOf(LibraryPack pack) => [
    for (final id in pack.levelIds) ?levelById(id)?.level,
  ];

  /// Everything that can be played: packs first, then single levels.
  List<CustomSelection> get selections => [
    for (final pack in _packs)
      if (levelsOf(pack) case final levels when levels.isNotEmpty)
        CustomSelection(
          key: 'pack:${pack.id}',
          name: pack.name,
          levels: levels,
        ),
    for (final (i, l) in _levels.indexed)
      CustomSelection(
        key: 'level:${l.id}',
        name: displayName(l.level, i),
        levels: [l.level],
      ),
  ];

  /// The level's own name, or a numbered fallback.
  static String displayName(CustomLevel level, int index) =>
      level.name.isNotEmpty ? level.name : '#${index + 1}';

  String _newId() {
    final random = Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    String id;
    do {
      id = String.fromCharCodes(
        List.generate(12, (_) => chars.codeUnitAt(random.nextInt(36))),
      );
    } while (levelById(id) != null || _packs.any((p) => p.id == id));
    return id;
  }

  /// Add a level; returns its id, or null when the library is full.
  String? add(CustomLevel level) {
    if (isFull) return null;
    final id = _newId();
    _levels.add(LibraryLevel(id, level));
    _changed();
    return id;
  }

  void update(String id, CustomLevel level) {
    final i = _levels.indexWhere((l) => l.id == id);
    if (i < 0) return;
    _levels[i] = LibraryLevel(id, level);
    _changed();
  }

  void remove(String id) {
    _levels.removeWhere((l) => l.id == id);
    for (var i = 0; i < _packs.length; i++) {
      final p = _packs[i];
      if (p.levelIds.contains(id)) {
        _packs[i] = LibraryPack(p.id, p.name, [
          for (final l in p.levelIds)
            if (l != id) l,
        ]);
      }
    }
    _changed();
  }

  /// Add or replace a pack. Returns false when there is no room.
  bool savePack({
    String? id,
    required String name,
    required List<String> levelIds,
  }) {
    final ids = [
      for (final l in levelIds)
        if (levelById(l) != null) l,
    ].take(CustomLevelLimits.maxLevelsPerPack).toList();
    final i = id == null ? -1 : _packs.indexWhere((p) => p.id == id);
    if (i >= 0) {
      _packs[i] = LibraryPack(id!, name, ids);
    } else {
      if (_packs.length >= maxPacks) return false;
      _packs.add(LibraryPack(_newId(), name, ids));
    }
    _changed();
    return true;
  }

  void removePack(String id) {
    _packs.removeWhere((p) => p.id == id);
    _changed();
  }

  /// Add levels from an import. Returns how many fitted.
  int addAll(Iterable<CustomLevel> levels) {
    var added = 0;
    for (final level in levels) {
      if (isFull) break;
      _levels.add(LibraryLevel(_newId(), level));
      added++;
    }
    if (added > 0) _changed();
    return added;
  }

  Future<void> _saving = Future.value();

  /// Completes once every change so far is stored.
  Future<void> flush() => _saving;

  void _changed() {
    final text = encode();
    // Chained, so an older write can never land after a newer one.
    _saving = _saving.then((_) => appSettings.setString(_key, text));
    notifyListeners();
  }

  @visibleForTesting
  String encode() => jsonEncode({
    'version': _version,
    'levels': [
      for (final l in _levels) {'id': l.id, ...l.level.toFileJson()},
    ],
    'packs': [
      for (final p in _packs)
        {'id': p.id, 'name': p.name, 'levels': p.levelIds},
    ],
  });

  void _load(String stored) {
    if (stored.isEmpty || stored.length > CustomLevelLimits.maxFileChars) {
      return;
    }
    final Object? json;
    try {
      json = jsonDecode(stored);
    } on FormatException {
      return;
    }
    if (json is! Map<String, dynamic> || json['version'] != _version) return;

    final ids = <String>{};
    if (json['levels'] case final List rawLevels) {
      for (final raw in rawLevels) {
        if (_levels.length >= CustomLevelLimits.maxLevelsPerFile) break;
        if (raw is! Map<String, dynamic>) continue;
        final id = raw['id'];
        final level = CustomLevel.fromFileJson(raw);
        if (id is! String || !_idPattern.hasMatch(id) || !ids.add(id)) {
          continue;
        }
        if (level == null) continue;
        _levels.add(LibraryLevel(id, level));
      }
    }
    if (json['packs'] case final List rawPacks) {
      for (final raw in rawPacks) {
        if (_packs.length >= maxPacks) break;
        if (raw is! Map<String, dynamic>) continue;
        final id = raw['id'];
        final name = raw['name'];
        final levelIds = raw['levels'];
        if (id is! String || !_idPattern.hasMatch(id) || !ids.add(id)) {
          continue;
        }
        if (name is! String || levelIds is! List) continue;
        _packs.add(
          LibraryPack(id, name, [
            for (final l in levelIds.take(CustomLevelLimits.maxLevelsPerPack))
              if (l is String && levelById(l) != null) l,
          ]),
        );
      }
    }
  }
}
