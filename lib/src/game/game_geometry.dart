/// Single source of truth for world-space sizes and the world scale factor.
///
/// ## Why a scale factor exists
///
/// Box2D's tolerance constants are ABSOLUTE lengths, tuned for objects roughly
/// 0.1-10 units across. They do not adapt to the size of your world:
///
///   forge2d 0.14.x (box2d v2)   linearSlop      0.005
///                               polygonRadius   0.010   (skin on every shape)
///                               aabbExtension   0.100   (AABB fattening)
///   forge2d 0.15.x (box2d v3)   B2_LINEAR_SLOP          0.005
///                               B2_SPECULATIVE_DISTANCE 0.020 (= 4x slop)
///                               B2_AABB_MARGIN          0.050
///
/// This game was originally built with a playfield 1.0 unit wide and a ball of
/// radius 0.02, which puts every one of those tolerances at the same order of
/// magnitude as the gameplay objects themselves -- polygonRadius alone was half
/// the ball's radius. Under box2d v3 the speculative distance (0.02) is wider
/// than the paddle was thick, so the ball generated contacts with the fatal
/// walls before touching them and the level reset in a loop.
///
/// [scale] lifts the whole simulation into the band box2d is tuned for. It is
/// a pure change of units: with time held constant, lengths and velocities
/// scale by `scale`, accelerations by `scale`, and angles/damping/friction not
/// at all. See the conversion helpers at the bottom of this class.
///
/// ## How to use it
///
/// World geometry should be expressed as one of the constants below, never as
/// a bare literal. Settings keep their natural, UNSCALED values everywhere they
/// are stored, transmitted, or edited (risetogether_config.json, the settings
/// UI, the LSL config push, the headless HTTP API) -- conversion happens
/// through [gravity], [velocity] and [distanceMultiplier] at the point of use.
/// That way a scale change cannot silently invalidate a deployed config file.
///
/// ## Vertical layout
///
/// Y is negative-going UP. The bottom (fatal) wall's inner face is at y = 0.
///
///     y =  0.00   ground, fatal
///     y = -0.01   paddle bottom face      <- [paddleBottomY]
///     y = -0.03   paddle top face         <- [paddleTopY], thickness 0.02
///     y = -0.05   ball centre at rest     <- [ballSpawnY], radius 0.02
///
/// (times [scale]).
abstract final class GameGeometry {
  /// The one knob. Multiplies every world length below.
  ///
  /// Bounded above by forge2d v2's `maxTranslation` (2.0 units per step): ball
  /// terminal velocity is `gravity / linearDamping` = 9.81 * scale, so at the
  /// 120 Hz headless tick a scale of 10 gives 0.82 units/step against that cap,
  /// and a scale of 50 would exceed it. Box2d v3's `maximumLinearSpeed` (400,
  /// settable on WorldDef) is the equivalent ceiling there.
  static const double scale = 10.0;

  // --- Base fractions of the level width -----------------------------------
  // These are the numbers that used to be inline literals scattered across
  // rise_together_world.dart, paddle.dart and wall.dart. Only `scale` above
  // should ever need to change.

  static const double _levelWidth = 1.0;
  static const double _ballRadius = 0.02;
  static const double _paddleHalfWidth = 0.15;
  static const double _paddleThickness = 0.02;

  /// Clearance between the paddle's bottom face and the fatal ground wall.
  static const double _paddleBottomY = -0.01;
  static const double _wallThickness = 0.01;
  static const double _groundDepth = 1.0;
  static const double _anchorRadius = 0.006;
  static const double _finishLineDepth = 0.04;

  // --- Derived world lengths -----------------------------------------------

  static const double levelWidth = _levelWidth * scale;
  static const double ballRadius = _ballRadius * scale;
  static const double paddleHalfWidth = _paddleHalfWidth * scale;
  static const double paddleThickness = _paddleThickness * scale;

  /// Bottom (down-facing) face of the paddle bar.
  static const double paddleBottomY = _paddleBottomY * scale;

  /// Top (up-facing) face of the paddle bar -- the surface the ball rests on.
  static const double paddleTopY = paddleBottomY - paddleThickness;

  /// Ball centre when resting on the paddle at spawn.
  static const double ballSpawnY = paddleTopY - ballRadius;

  /// Thickness of the side and level-end walls.
  static const double wallThickness = _wallThickness * scale;

  /// How far the bottom (fatal) wall extends downward, away from the playfield.
  static const double groundDepth = _groundDepth * scale;

  /// Radius of the paddle's centre marker (visual only).
  static const double anchorRadius = _anchorRadius * scale;

  /// How far the finish-line stripe reaches into the playfield (visual only).
  static const double finishLineDepth = _finishLineDepth * scale;

  // --- Team label (world-space text) ---------------------------------------
  //
  // TextComponent lays out in its own pre-scale units (fontSize, shadow offset
  // and blur, and `size`) and is then mapped into world space by `scale`. So
  // only `scale` and `position` are world lengths; the rest must stay put or
  // the text distorts rather than resizes.

  /// Layout box width for the team label, in the component's pre-scale units.
  static const double teamLabelBoxWidth = _levelWidth;

  /// Maps the label's pre-scale units into world space.
  static const double teamLabelScale = 0.1 * scale;

  /// Label position below the top of the playfield, in world units.
  static const double teamLabelY = 0.1 * scale;

  /// An absolute world length declared elsewhere as a level-1-relative value,
  /// e.g. the `zoneHeightMeters` in [LevelSpawnConfig] spawn definitions.
  static double length(double base) => base * scale;

  // --- Settings conversions, applied at READ time only ----------------------
  //
  // Never write these back into settings storage. See the class docs.

  /// Acceleration (L/T^2): `physics.gravity`.
  static double gravity(double raw) => raw * scale;

  /// Linear velocity (L/T): `physics.thrust_multiplier` is used directly as an
  /// upward velocity in [Paddle.update].
  static double velocity(double raw) => raw * scale;

  /// Metres represented per game unit: `game.distance_multiplier`. Inversely
  /// proportional, so reported distances are unchanged by a scale change.
  static double distanceMultiplier(double raw) => raw / scale;
}
