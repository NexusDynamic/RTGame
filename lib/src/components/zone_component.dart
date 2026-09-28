import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// The [ZoneComponent] is for representing a zone in the game.
///
/// It is a solid rectangle covering the zone area, filled with a repeating
/// diagonal hazard stripe.
///
/// Per-frame cost is a single `drawPath` with a cached path (see
/// [RectangleComponent]/[PolygonComponent]) and no allocations, so there is
/// nothing to do at render time. What is worth avoiding is rebuilding the
/// gradient: [LevelObjectPool] is a registry rather than a pool and always
/// constructs fresh objects, so every level advance would otherwise compile a
/// new shader for each zone in each of the two team worlds.
class ZoneComponent extends RectangleComponent {
  /// Built once and shared. The gradient is defined over a 1x1 tile with
  /// [TileMode.repeated], so it does not depend on the zone's size and is safe
  /// to reuse across every zone. Only the [Shader] is shared -- each component
  /// still gets its own [Paint], since Flame treats a component's paint as
  /// mutable state.
  static final Shader _stripeShader = const LinearGradient(
    tileMode: TileMode.repeated,
    begin: Alignment.centerLeft,
    end: Alignment(-0.4, -0.8),
    stops: [0.0, 0.5, 0.5, 1],
    colors: [
      Color.fromARGB(255, 173, 173, 0),
      Color.fromARGB(255, 173, 173, 0),
      Color.fromARGB(255, 0, 0, 0),
      Color.fromARGB(255, 0, 0, 0),
    ],
  ).createShader(const Rect.fromLTWH(0, 0, 1.0000, 1.0000));

  ZoneComponent({required Vector2 size})
    : super(
        size: size,
        anchor: Anchor.center,
        paint: Paint()
          ..style = PaintingStyle.fill
          ..shader = _stripeShader,
      );
}
