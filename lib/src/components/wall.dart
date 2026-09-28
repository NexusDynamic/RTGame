import 'dart:math' show min, max;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/rendering.dart';
import 'package:rise_together_game/src/game/game_geometry.dart';
import 'package:rise_together_game/src/game/rise_together_game.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:rise_together_game/src/game/rise_together_world.dart';

class Wall extends BodyComponent<RiseTogetherGameBase<RiseTogetherWorld>> {
  final Vector2 _start;
  final Vector2 _end;
  final bool isFatal;
  final bool isLevelEnd;
  final bool usePolygon;
  final Image? image;

  @override
  RiseTogetherWorld get world => _world;
  final RiseTogetherWorld _world;

  Wall(
    this._world,
    this._start,
    this._end, {
    this.isFatal = true,
    this.isLevelEnd = false,
    super.paint,
    this.usePolygon = false,
    this.image,
  });

  @override
  Body createBody() {
    // forge2d box2d v3
    final ShapeGeometry shape;
    // forge2d box2d v2
    // final Shape shape;
    if (usePolygon) {
      final vertices = [
        _start,
        Vector2(_end.x, _start.y),
        _end,
        Vector2(_start.x, _end.y),
      ];
      // forge2d box2d v3
      shape = Polygon(vertices);
      // shape = PolygonShape()..set(vertices);
    } else {
      // forge2d box2d v3
      shape = Segment(point1: _start, point2: _end);
      // forge2d box2d v2
      // shape = EdgeShape()..set(_start, _end);
    }
    // forge2d box2d v3
    final fixtureDef = ShapeDef(
      material: SurfaceMaterial(friction: 0.3),
      density: 1.0,
      enableContactEvents: true,
    );
    // forge2d box2d v2
    // final fixtureDef = FixtureDef(shape, friction: 0.3);

    final bodyDef = BodyDef(
      userData: this,
      position: Vector2.zero(),
      // forge2d box2d v3
      gravityScale: 0,
      allowFastRotation: false,
    );
    // forge2d box2d v3
    return _world.createBody(bodyDef)..createShape(shape, fixtureDef);
    // forge2d box2d v2
    // return _world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  /// The ground image's draw call, recorded once.
  ///
  /// [paintImage] allocates a Paint, runs applyBoxFit and clips on every call,
  /// from inputs that never change — and this ran every frame, for each of the
  /// two team worlds. Recording it replays the identical ops (a Picture is a
  /// display list, so it re-rasterises under the current camera transform and
  /// stays sharp at any zoom) for one draw call and no allocations.
  Picture? _imagePicture;

  @override
  void renderTree(Canvas canvas) {
    if (_imagePicture != null) {
      canvas.drawPicture(_imagePicture!);
    }
    super.renderTree(canvas);
  }

  @override
  void onRemove() {
    _imagePicture?.dispose();
    _imagePicture = null;
    super.onRemove();
  }

  @override
  Future<void> onLoad() async {
    // Never render the physics body. The level-end wall used to, but its paint
    // is fully transparent (see RiseTogetherWorld._addBoundaries), so it cost a
    // save/drawLine/restore plus two Offset allocations per frame to draw
    // nothing. Its visible part is the finish-line stripe added below.
    renderBody = false;

    final image = this.image;
    if (image != null) {
      final recorder = PictureRecorder();
      paintImage(
        canvas: Canvas(recorder),
        rect: Rect.fromLTRB(_start.x, _start.y, _end.x, _end.y),
        image: image,
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
      );
      _imagePicture = recorder.endRecording();
    }

    if (isLevelEnd) {
      // Inner face of wall is where the ball hits (max y = less negative = closer to ball).
      final innerY = max(_start.y, _end.y);
      final width = max(_start.x, _end.x) - min(_start.x, _end.x);
      // The stripe is anchored topCenter, so its x is the wall's right edge --
      // this was a hardcoded 0.5, i.e. width / 2 at a level width of 1.
      add(
        _FinishLineComponent(
          position: Vector2(max(_start.x, _end.x), innerY),
          width: width,
        ),
      );
    }
    await super.onLoad();
  }

  @override
  String toString() {
    return 'Wall(start: $_start, end: $_end, isFatal: $isFatal)';
  }
}

/// Checkerboard finish-line stripe drawn just below the top wall's inner face.
/// Rendered as a child of the wall BodyComponent so it sits in world space
/// without touching the physics body's renderTree/render path.
class _FinishLineComponent extends PositionComponent {
  static const _cols = 30;
  static const _rows = 2;
  static const _visualHeight = GameGeometry.finishLineDepth;

  static final Paint _blackPaint = Paint()..color = const Color(0xFF1A1A1A);
  static final Paint _whitePaint = Paint()..color = const Color(0xFFF0F0F0);

  final double _width;

  /// The full strip, painted black; the white squares then go on top. The union
  /// of the 60 checkerboard squares is exactly this rect, so the result is the
  /// same image the per-square loop produced.
  late final Rect _backdrop;

  /// The 30 white squares as a single path, built once.
  late final Path _whiteSquares;

  _FinishLineComponent({required Vector2 position, required double width})
    : _width = width,
      super(
        position: position,
        size: Vector2(width, _visualHeight),
        anchor: Anchor.topCenter,
      );

  @override
  Future<void> onLoad() async {
    final sqW = _width / _cols;
    final sqH = _visualHeight / _rows;

    _backdrop = Rect.fromLTWH(-_width / 2, 0, _width, _visualHeight);
    _whiteSquares = Path();
    for (var col = 0; col < _cols; col++) {
      for (var row = 0; row < _rows; row++) {
        if ((col + row).isEven) continue; // black; covered by the backdrop
        _whiteSquares.addRect(
          Rect.fromLTWH(
            col * sqW - _width / 2, // centered on anchor (topCenter)
            row * sqH,
            sqW,
            sqH,
          ),
        );
      }
    }
    await super.onLoad();
  }

  // Two draw calls and no allocations. This used to run a 30x2 loop issuing 60
  // drawRect calls and allocating 60 Paints per frame -- doubled by the two team
  // worlds, and paid even while the finish line was far off-screen, since Flame
  // does no frustum culling.
  @override
  void render(Canvas canvas) {
    canvas.drawRect(_backdrop, _blackPaint);
    canvas.drawPath(_whiteSquares, _whitePaint);
  }
}
