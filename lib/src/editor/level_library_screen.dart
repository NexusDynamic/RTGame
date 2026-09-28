import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:rise_together_game/src/editor/level_editor_screen.dart';
import 'package:rise_together_game/src/editor/level_transfer.dart';
import 'package:rise_together_game/src/game/level_sequence.dart';
import 'package:rise_together_game/src/levels/custom_level.dart';
import 'package:rise_together_game/src/levels/level_library.dart';
import 'package:rise_together_game/src/levels/solo_progress.dart';
import 'package:rise_together_game/src/ui/solo_game_screen.dart';

/// The player's levels and packs: create, edit, play, import and export.
class LevelLibraryScreen extends StatefulWidget {
  const LevelLibraryScreen({super.key});

  @override
  State<LevelLibraryScreen> createState() => _LevelLibraryScreenState();
}

class _LevelLibraryScreenState extends State<LevelLibraryScreen> {
  final _library = LevelLibrary();

  @override
  void initState() {
    super.initState();
    _library.addListener(_rebuild);
  }

  @override
  void dispose() {
    _library
      ..removeListener(_rebuild)
      ..dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _edit([String? id]) => Navigator.of(context).push(
    MaterialPageRoute<bool>(
      builder: (_) => LevelEditorScreen(library: _library, levelId: id),
    ),
  );

  void _play(CustomSelection selection) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SoloGameScreen(
          timed: false,
          sequence: LevelSequence.custom(selection.levels),
          customRunKey: SoloProgress.customRunKey(selection.key),
        ),
      ),
    );
  }

  Future<void> _import() async {
    final levels = await LevelTransfer.import(context);
    if (levels == null || !mounted) return;
    final added = _library.addAll(levels);
    _snack(
      added == levels.length
          ? 'library.imported'.tr(args: ['$added'])
          : 'library.importedSome'.tr(args: ['$added', '${levels.length}']),
    );
  }

  Future<bool> _confirmDelete(String name) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('library.deleteTitle'.tr(args: [name])),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('online.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('editor.delete'.tr()),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _editPack([LibraryPack? pack]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _PackDialog(library: _library, pack: pack),
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: Text('library.title'.tr()),
        actions: [
          IconButton(
            tooltip: 'library.import'.tr(),
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _library.isFull ? null : _import,
          ),
          IconButton(
            tooltip: 'library.exportAll'.tr(),
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _library.levels.isEmpty
                ? null
                : () => LevelTransfer.export(context, [
                    for (final l in _library.levels) l.level,
                  ], fileName: 'rise-together-levels'),
          ),
        ],
        bottom: TabBar(
          tabs: [
            Tab(text: 'library.levels'.tr()),
            Tab(text: 'library.packs'.tr()),
          ],
        ),
      ),
      floatingActionButton: Builder(
        builder: (context) => FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: Text('library.new'.tr()),
          onPressed: () {
            if (DefaultTabController.of(context).index == 0) {
              if (_library.isFull) {
                _snack(
                  'library.full'.tr(
                    args: ['${CustomLevelLimits.maxLevelsPerFile}'],
                  ),
                );
                return;
              }
              _edit();
            } else {
              _editPack();
            }
          },
        ),
      ),
      body: TabBarView(children: [_levelsTab(), _packsTab()]),
    ),
  );

  Widget _empty(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );

  Widget _levelsTab() {
    final levels = _library.levels;
    if (levels.isEmpty) return _empty('library.noLevels'.tr());
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: levels.length,
      itemBuilder: (context, i) {
        final entry = levels[i];
        final name = LevelLibrary.displayName(entry.level, i);
        return ListTile(
          title: Text(name),
          subtitle: Text(
            'library.levelSummary'.tr(
              args: [
                entry.level.heightMultiplier.toStringAsFixed(1),
                '${entry.level.objects.length}',
              ],
            ),
          ),
          onTap: () => _edit(entry.id),
          trailing: PopupMenuButton<String>(
            onSelected: (action) async {
              switch (action) {
                case 'play':
                  _play(
                    CustomSelection(
                      key: 'level:${entry.id}',
                      name: name,
                      levels: [entry.level],
                    ),
                  );
                case 'duplicate':
                  if (_library.add(entry.level) == null) {
                    _snack(
                      'library.full'.tr(
                        args: ['${CustomLevelLimits.maxLevelsPerFile}'],
                      ),
                    );
                  }
                case 'export':
                  await LevelTransfer.export(context, [
                    entry.level,
                  ], fileName: name);
                case 'delete':
                  if (await _confirmDelete(name)) _library.remove(entry.id);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'play', child: Text('library.play'.tr())),
              PopupMenuItem(
                value: 'duplicate',
                child: Text('library.duplicate'.tr()),
              ),
              PopupMenuItem(
                value: 'export',
                child: Text('library.export'.tr()),
              ),
              PopupMenuItem(value: 'delete', child: Text('editor.delete'.tr())),
            ],
          ),
        );
      },
    );
  }

  Widget _packsTab() {
    final packs = _library.packs;
    if (packs.isEmpty) return _empty('library.noPacks'.tr());
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: packs.length,
      itemBuilder: (context, i) {
        final pack = packs[i];
        final levels = _library.levelsOf(pack);
        final name = pack.name.isEmpty
            ? 'library.untitledPack'.tr()
            : pack.name;
        return ListTile(
          title: Text(name),
          subtitle: Text('library.packSummary'.tr(args: ['${levels.length}'])),
          onTap: () => _editPack(pack),
          trailing: PopupMenuButton<String>(
            onSelected: (action) async {
              switch (action) {
                case 'play':
                  _play(
                    CustomSelection(
                      key: 'pack:${pack.id}',
                      name: name,
                      levels: levels,
                    ),
                  );
                case 'export':
                  await LevelTransfer.export(context, levels, fileName: name);
                case 'delete':
                  if (await _confirmDelete(name)) _library.removePack(pack.id);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'play',
                enabled: levels.isNotEmpty,
                child: Text('library.play'.tr()),
              ),
              PopupMenuItem(
                value: 'export',
                enabled: levels.isNotEmpty,
                child: Text('library.export'.tr()),
              ),
              PopupMenuItem(value: 'delete', child: Text('editor.delete'.tr())),
            ],
          ),
        );
      },
    );
  }
}

/// Name a pack and choose its levels, in order.
class _PackDialog extends StatefulWidget {
  const _PackDialog({required this.library, this.pack});

  final LevelLibrary library;
  final LibraryPack? pack;

  @override
  State<_PackDialog> createState() => _PackDialogState();
}

class _PackDialogState extends State<_PackDialog> {
  late final _name = TextEditingController(text: widget.pack?.name ?? '');
  late final List<String> _ids = [...?widget.pack?.levelIds];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final saved = widget.library.savePack(
      id: widget.pack?.id,
      name: _name.text,
      levelIds: _ids,
    );
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'library.packsFull'.tr(args: ['${LevelLibrary.maxPacks}']),
          ),
        ),
      );
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final levels = widget.library.levels;
    String nameOf(String id) {
      final i = levels.indexWhere((l) => l.id == id);
      return i < 0 ? '?' : LevelLibrary.displayName(levels[i].level, i);
    }

    final full = _ids.length >= CustomLevelLimits.maxLevelsPerPack;
    return AlertDialog(
      title: Text(
        widget.pack == null ? 'library.newPack'.tr() : 'library.editPack'.tr(),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              maxLength: CustomLevelLimits.maxNameLength,
              decoration: InputDecoration(labelText: 'library.packName'.tr()),
            ),
            Text(
              'library.packOrder'.tr(
                args: [
                  '${_ids.length}',
                  '${CustomLevelLimits.maxLevelsPerPack}',
                ],
              ),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Flexible(
              child: ReorderableListView(
                shrinkWrap: true,
                buildDefaultDragHandles: true,
                onReorderItem: (from, to) =>
                    setState(() => _ids.insert(to, _ids.removeAt(from))),
                children: [
                  for (final (i, id) in _ids.indexed)
                    ListTile(
                      key: ValueKey('$i:$id'),
                      dense: true,
                      leading: Text('${i + 1}'),
                      title: Text(nameOf(id)),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => setState(() => _ids.removeAt(i)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            MenuAnchor(
              builder: (context, controller, _) => OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: Text('library.addLevel'.tr()),
                onPressed: full || levels.isEmpty
                    ? null
                    : () => controller.isOpen
                          ? controller.close()
                          : controller.open(),
              ),
              menuChildren: [
                for (final (i, l) in levels.indexed)
                  MenuItemButton(
                    onPressed: () => setState(() => _ids.add(l.id)),
                    child: Text(LevelLibrary.displayName(l.level, i)),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('online.cancel'.tr()),
        ),
        FilledButton(
          onPressed: _ids.isEmpty ? null : _save,
          child: Text('editor.save'.tr()),
        ),
      ],
    );
  }
}

/// Let the player pick custom levels to play. Null if they cancel or have
/// none.
Future<CustomSelection?> pickCustomLevels(BuildContext context) async {
  final library = LevelLibrary();
  final selections = library.selections;
  library.dispose();
  return showModalBottomSheet<CustomSelection>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: selections.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'library.noLevels'.tr(),
                  textAlign: TextAlign.center,
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  ListTile(title: Text('library.pickTitle'.tr())),
                  for (final s in selections)
                    ListTile(
                      leading: Icon(
                        s.key.startsWith('pack:')
                            ? Icons.collections_bookmark_outlined
                            : Icons.terrain_outlined,
                      ),
                      title: Text(s.name),
                      subtitle: Text(
                        'library.packSummary'.tr(args: ['${s.levels.length}']),
                      ),
                      onTap: () => Navigator.pop(context, s),
                    ),
                ],
              ),
      ),
    ),
  );
}
