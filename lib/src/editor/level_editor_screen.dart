import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:rise_together_game/src/game/game_geometry.dart';
import 'package:rise_together_game/src/game/level_sequence.dart';
import 'package:rise_together_game/src/levels/custom_level.dart';
import 'package:rise_together_game/src/levels/level_library.dart';
import 'package:rise_together_game/src/ui/solo_game_screen.dart';

/// How each object type looks in the editor, matching the game's sprites.
extension CustomObjectTypeLook on CustomObjectType {
  String? get sprite => switch (this) {
    CustomObjectType.fatal => 'assets/images/obstacle_fatal.png',
    CustomObjectType.powerupWidth => 'assets/images/powerup_paddle_width.png',
    CustomObjectType.powerdownWidth =>
      'assets/images/powerdown_paddle_width.png',
    CustomObjectType.controlReversal =>
      'assets/images/trigger_control_reversal.png',
    CustomObjectType.controlReversalZone => null,
  };

  String get label => 'editor.types.$name'.tr();

  String get help => 'editor.typeHelp.$name'.tr();

  /// Parameter label and a formatted value.
  String paramLabel(double value) => switch (this) {
    CustomObjectType.powerupWidth || CustomObjectType.powerdownWidth =>
      'editor.params.width'.tr(args: ['×${value.toStringAsFixed(2)}']),
    CustomObjectType.controlReversal => 'editor.params.duration'.tr(
      args: [value.toStringAsFixed(0)],
    ),
    CustomObjectType.controlReversalZone => 'editor.params.zoneHeight'.tr(
      args: [value.toStringAsFixed(1)],
    ),
    CustomObjectType.fatal => '',
  };
}

const _zoneColor = Color(0x669C27B0);

/// Build or change one level.
///
/// Tap empty space to place the selected object type, tap an object to
/// select it, and long-press an object to drag it. Pops with true if the level
/// was saved.
class LevelEditorScreen extends StatefulWidget {
  const LevelEditorScreen({super.key, required this.library, this.levelId});

  final LevelLibrary library;

  /// The level to edit; null starts a new one.
  final String? levelId;

  @override
  State<LevelEditorScreen> createState() => _LevelEditorScreenState();
}

class _LevelEditorScreenState extends State<LevelEditorScreen> {
  late CustomLevel _level;
  late String? _id = widget.levelId;
  bool _dirty = false;
  CustomObjectType _tool = CustomObjectType.fatal;
  int? _selected;

  /// Index of the object being dragged.
  int? _dragging;

  final _canvasKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _level =
        widget.library.levelById(widget.levelId ?? '')?.level ??
        CustomLevel.create(heightMultiplier: 3)!;
  }

  void _set(CustomLevel? level, {int? select}) {
    if (level == null) return;
    setState(() {
      _level = level;
      _dirty = true;
      _selected = select;
    });
  }

  /// Lowest height every object still fits in.
  double get _minHeight {
    var top = CustomLevelLimits.minHeight * CustomLevelLimits.levelWidth;
    for (final o in _level.objects) {
      top = math.max(top, o.y + o.size.$2 / 2);
    }
    final steps = (top / CustomLevelLimits.levelWidth * 100).ceil();
    return math.min(steps / 100, CustomLevelLimits.maxHeight);
  }

  void _place(double x, double y) {
    if (_level.objects.length >= CustomLevelLimits.maxObjects) {
      _snack('editor.full'.tr(args: ['${CustomLevelLimits.maxObjects}']));
      return;
    }
    final param = _tool.param?.fallback;
    final (cx, cy) = CustomObject.clampPosition(
      _tool,
      param,
      x,
      y,
      _level.height,
    );
    final object = CustomObject.create(
      type: _tool,
      x: cx,
      y: cy,
      param: param,
      levelHeight: _level.height,
    );
    if (object == null) {
      _snack('editor.noRoom'.tr());
      return;
    }
    _set(
      _level.copyWith(objects: [..._level.objects, object]),
      select: _level.objects.length,
    );
  }

  void _move(int index, double x, double y) {
    final o = _level.objects[index];
    final (cx, cy) = CustomObject.clampPosition(
      o.type,
      o.param,
      x,
      y,
      _level.height,
    );
    final moved = o.moved(x: cx, y: cy, levelHeight: _level.height);
    if (moved == null) return;
    _set(
      _level.copyWith(objects: [..._level.objects]..[index] = moved),
      select: index,
    );
  }

  void _setParam(int index, double value) {
    final o = _level.objects[index];
    final (cx, cy) = CustomObject.clampPosition(
      o.type,
      value,
      o.x,
      o.y,
      _level.height,
    );
    final changed = CustomObject.create(
      type: o.type,
      x: cx,
      y: cy,
      param: value,
      levelHeight: _level.height,
    );
    if (changed == null) return;
    _set(
      _level.copyWith(objects: [..._level.objects]..[index] = changed),
      select: index,
    );
  }

  void _delete(int index) =>
      _set(_level.copyWith(objects: [..._level.objects]..removeAt(index)));

  void _snack(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _rename() async {
    final controller = TextEditingController(text: _level.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('editor.rename'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: CustomLevelLimits.maxNameLength,
          decoration: InputDecoration(hintText: 'editor.nameHint'.tr()),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('online.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text('editor.ok'.tr()),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null) _set(_level.copyWith(name: name), select: _selected);
  }

  bool _save() {
    final id = _id;
    if (id == null) {
      final newId = widget.library.add(_level);
      if (newId == null) {
        _snack(
          'library.full'.tr(args: ['${CustomLevelLimits.maxLevelsPerFile}']),
        );
        return false;
      }
      _id = newId;
    } else {
      widget.library.update(id, _level);
    }
    setState(() => _dirty = false);
    _snack('editor.saved'.tr());
    return true;
  }

  void _testPlay() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SoloGameScreen(
          timed: false,
          sequence: LevelSequence.custom([_level]),
        ),
      ),
    );
  }

  Future<void> _onPopInvoked(bool didPop, Object? _) async {
    if (didPop) return;
    final navigator = Navigator.of(context);
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('editor.unsavedTitle'.tr()),
        content: Text('editor.unsavedMessage'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('editor.discard'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('editor.save'.tr()),
          ),
        ],
      ),
    );
    if (choice == null) return;
    if (choice && !_save()) return;
    navigator.pop(_id != null);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        appBar: AppBar(
          title: InkWell(
            onTap: _rename,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _level.name.isEmpty ? 'editor.untitled'.tr() : _level.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.edit, size: 18),
              ],
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'editor.testPlay'.tr(),
              icon: const Icon(Icons.play_arrow),
              onPressed: _testPlay,
            ),
            IconButton(
              tooltip: 'editor.save'.tr(),
              icon: const Icon(Icons.save),
              onPressed: _dirty || _id == null ? _save : null,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(child: _canvas()),
              const Divider(height: 1),
              if (selected != null && selected < _level.objects.length)
                _selectionPanel(selected)
              else
                _toolPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolPanel() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final type in CustomObjectType.values)
              ChoiceChip(
                avatar: _TypeIcon(type, size: 20),
                label: Text(type.label),
                tooltip: type.help,
                selected: _tool == type,
                onSelected: (_) => setState(() => _tool = type),
              ),
          ],
        ),
        Row(
          children: [
            Text('editor.height'.tr()),
            Expanded(
              child: Slider(
                min: CustomLevelLimits.minHeight,
                max: CustomLevelLimits.maxHeight,
                divisions:
                    ((CustomLevelLimits.maxHeight -
                                CustomLevelLimits.minHeight) *
                            2)
                        .round(),
                value: _level.heightMultiplier,
                label: '×${_level.heightMultiplier.toStringAsFixed(1)}',
                onChanged: (v) => _set(
                  _level.copyWith(heightMultiplier: math.max(v, _minHeight)),
                ),
              ),
            ),
            Text(
              'editor.objectCount'.tr(
                args: [
                  '${_level.objects.length}',
                  '${CustomLevelLimits.maxObjects}',
                ],
              ),
            ),
          ],
        ),
        Text(
          'editor.hint'.tr(),
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );

  Widget _selectionPanel(int index) {
    final o = _level.objects[index];
    final spec = o.type.param;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _TypeIcon(o.type, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  o.type.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'editor.delete'.tr(),
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(index),
              ),
              IconButton(
                tooltip: 'editor.done'.tr(),
                icon: const Icon(Icons.check),
                onPressed: () => setState(() => _selected = null),
              ),
            ],
          ),
          if (spec != null)
            Row(
              children: [
                SizedBox(width: 140, child: Text(o.type.paramLabel(o.param!))),
                Expanded(
                  child: Slider(
                    min: spec.min,
                    max: spec.max,
                    value: o.param!,
                    onChanged: (v) => _setParam(index, v),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _canvas() => LayoutBuilder(
    builder: (context, constraints) {
      // Fit the width, capped so a wide window still shows a tall column.
      final width = math.min(constraints.maxWidth - 32, 480.0);
      final scale = width / CustomLevelLimits.levelWidth;
      final height = _level.height * scale;

      (double, double) toWorld(Offset p) => (
        p.dx / scale - CustomLevelLimits.levelWidth / 2,
        (height - p.dy) / scale,
      );

      Rect rectOf(CustomObject o) {
        final (w, h) = o.size;
        return Rect.fromCenter(
          center: Offset(
            (o.x + CustomLevelLimits.levelWidth / 2) * scale,
            height - o.y * scale,
          ),
          width: w * scale,
          height: h * scale,
        );
      }

      return SingleChildScrollView(
        // Start at the bottom, where the ball does.
        reverse: true,
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            key: _canvasKey,
            width: width,
            height: height,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                if (_selected != null) {
                  setState(() => _selected = null);
                  return;
                }
                final (x, y) = toWorld(d.localPosition);
                _place(x, y);
              },
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _BackdropPainter(
                        scale: scale,
                        levelHeight: _level.height,
                        colors: Theme.of(context).colorScheme,
                      ),
                    ),
                  ),
                  // Zones first so squares on top of them stay tappable.
                  for (final (i, o)
                      in _level.objects.indexed.toList()..sort(
                        (a, b) => a.$2.type.isZone == b.$2.type.isZone
                            ? 0
                            : a.$2.type.isZone
                            ? -1
                            : 1,
                      ))
                    Positioned.fromRect(
                      rect: rectOf(o),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _selected = i),
                        onLongPressStart: (_) => setState(() {
                          _dragging = i;
                          _selected = i;
                        }),
                        onLongPressMoveUpdate: (d) {
                          final box = _canvasKey.currentContext
                              ?.findRenderObject();
                          if (_dragging != i || box is! RenderBox) return;
                          final (x, y) = toWorld(
                            box.globalToLocal(d.globalPosition),
                          );
                          _move(i, x, y);
                        },
                        onLongPressEnd: (_) => setState(() => _dragging = null),
                        child: _ObjectView(
                          o,
                          selected: _selected == i,
                          dragging: _dragging == i,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _TypeIcon extends StatelessWidget {
  const _TypeIcon(this.type, {required this.size});

  final CustomObjectType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final sprite = type.sprite;
    return SizedBox.square(
      dimension: size,
      child: sprite == null
          ? const DecoratedBox(
              decoration: BoxDecoration(color: _zoneColor),
              child: Icon(Icons.swap_horiz, size: 16),
            )
          : Image.asset(sprite, fit: BoxFit.contain),
    );
  }
}

class _ObjectView extends StatelessWidget {
  const _ObjectView(
    this.object, {
    required this.selected,
    this.dragging = false,
  });

  final CustomObject object;
  final bool selected;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final sprite = object.type.sprite;
    final outline = selected
        ? Border.all(
            color: Theme.of(context).colorScheme.primary,
            width: dragging ? 3 : 2,
          )
        : null;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(border: outline),
      child: sprite == null
          ? const ColoredBox(
              color: _zoneColor,
              child: Center(child: Icon(Icons.swap_horiz, color: Colors.white)),
            )
          : Image.asset(sprite, fit: BoxFit.fill),
    );
  }
}

/// Grid, start area, paddle and finish line.
class _BackdropPainter extends CustomPainter {
  _BackdropPainter({
    required this.scale,
    required this.levelHeight,
    required this.colors,
  });

  final double scale;
  final double levelHeight;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF101828),
    );

    // A line every 5 units, labelled with the height.
    final grid = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    for (var y = 5.0; y < levelHeight; y += 5) {
      final py = size.height - y * scale;
      canvas.drawLine(Offset(0, py), Offset(size.width, py), grid);
      final label = TextPainter(
        text: TextSpan(
          text: y.toStringAsFixed(0),
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(2, py - label.height));
    }

    // Nothing may be placed where the ball starts.
    final clearance = CustomLevelLimits.spawnClearance * scale;
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - clearance, size.width, clearance),
      Paint()..color = Colors.white10,
    );

    // Paddle and ball at their start positions.
    final paddleHalf = GameGeometry.paddleHalfWidth * scale;
    final paddleY = size.height + GameGeometry.paddleTopY * scale;
    canvas.drawRect(
      Rect.fromLTRB(
        size.width / 2 - paddleHalf,
        paddleY,
        size.width / 2 + paddleHalf,
        paddleY + GameGeometry.paddleThickness * scale,
      ),
      Paint()..color = colors.primary,
    );
    canvas.drawCircle(
      Offset(size.width / 2, size.height + GameGeometry.ballSpawnY * scale),
      GameGeometry.ballRadius * scale,
      Paint()..color = Colors.white,
    );

    // Finish line.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, GameGeometry.finishLineDepth * scale),
      Paint()..color = Colors.greenAccent.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      old.scale != scale ||
      old.levelHeight != levelHeight ||
      old.colors != colors;
}
