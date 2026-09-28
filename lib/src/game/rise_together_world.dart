import 'dart:async';
import 'package:flame/components.dart' hide Matrix4;
import 'package:flame/flame.dart';
import 'package:flame/image_composition.dart' hide Matrix4;
import 'package:flame/layers.dart';
import 'package:flame/parallax.dart';
import 'package:flame_forge2d/flame_forge2d.dart' as forge2d;
import 'package:flutter/material.dart' hide Image;
import 'package:rise_together_game/src/attributes/resetable.dart';
import 'package:rise_together_game/src/attributes/team_color_provider.dart';
import 'package:rise_together_game/src/game/game_geometry.dart';
import 'package:rise_together_game/src/game/rise_together_levels.dart';
import 'package:rise_together_game/src/game/world_controller.dart';
import 'package:rise_together_game/src/models/team_context.dart';
import 'package:rise_together_game/src/components/ball.dart';
import 'package:rise_together_game/src/components/wall.dart';
import 'package:rise_together_game/src/models/team.dart';
import 'package:rise_together_game/src/net/game_session.dart';
import 'package:rise_together_game/src/services/app_logging.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';
import 'rise_together_game.dart';
import 'package:rise_together_game/src/components/paddle.dart';
import 'package:rise_together_game/src/game/level_spawn_config.dart';
import 'package:rise_together_game/src/game/level_object_pool.dart';
import 'package:rise_together_game/src/components/level_object.dart';

class BackgroundLayer extends PreRenderedLayer {
  RiseTogetherLevel _level;
  RiseTogetherLevel get level => _level;
  bool _ready = false;
  late Rect rect;
  late Paint paint;

  BackgroundLayer(this._level) {
    _initBackground();
  }

  set level(RiseTogetherLevel newLevel) {
    _level = newLevel;
    _initBackground();
  }

  void _initBackground() {
    rect = Rect.fromLTWH(
      -RiseTogetherLevel.horizontalWidth / 2,
      -RiseTogetherLevel.horizontalWidth * level.verticalMultiplier,
      RiseTogetherLevel.horizontalWidth,
      RiseTogetherLevel.horizontalWidth * level.verticalMultiplier,
    );
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      // cool to warm
      colors: [
        const Color.fromARGB(255, 0, 0, 0),
        const Color.fromARGB(255, 17, 17, 54),
      ],
    );
    paint = Paint()
      ..shader = gradient.createShader(rect)
      ..blendMode = BlendMode.lighten;
    _ready = true;
  }

  @override
  void drawLayer() {
    if (!_ready) return;
    canvas.drawRect(rect, paint);
  }
}

/// Parallax scroll per world-unit/second of paddle rise. Increase to scroll
/// faster.
///
/// The conversion is from the paddle's *world velocity*, not from raw thrust.
/// Thrust is a normalised 0..1 team input; the speed it actually produces is
/// `GameGeometry.velocity(physics.thrust_multiplier) * thrust` (see
/// [Paddle.update]). Scrolling the background on the bare thrust instead left
/// the girders moving at a rate that had nothing to do with how fast you were
/// rising: at `thrust_multiplier = 0.2` the paddle climbs at a fifth of the
/// default rate while the background kept scrolling at the full one. Most
/// visible in the individual condition, where one participant supplies the
/// whole team's thrust and so reaches `totalThrust = 1.0` alone.
///
/// 0.025 is chosen so that at the default `thrust_multiplier` of 1.0 and
/// [GameGeometry.scale] of 10 this reproduces the previous constant (0.25)
/// except the flame engine update means that the constant had to change
/// to match.
const double kParallaxPerWorldVelocity = 0.128;

/// Parallax base velocity for a normalised [totalThrust] (0..1).
///
/// Shared by the authoritative path ([RiseTogetherWorld.update]) and the
/// follower path (`_interpolatePhysicsState`) so every game mode scrolls at the
/// same speed for the same input. They were two copies of the same expression,
/// which is exactly how they would drift.
Vector2 parallaxVelocityForThrust(
  double totalThrust,
  double thrustMultiplierSetting,
) => Vector2(
  0,
  -GameGeometry.velocity(thrustMultiplierSetting) *
      totalThrust *
      kParallaxPerWorldVelocity,
);

class RiseTogetherWorld extends forge2d.Forge2DWorld
    with
        HasGameRef<RiseTogetherGameBase>,
        AppLogging,
        AppSettings,
        TeamColorProvider,
        Resetable {
  late final ParallaxComponent? parallax;

  /// Null when this world is never rendered: the opponent's world in the
  /// single-view layout has no camera at all, and the headless build has none
  /// for either world. Every use must therefore be guarded -- see
  /// [hasWorldCamera].
  CameraComponent? _worldCamera;
  RectangleComponent? _viewportOverlay;
  late Ball ball;
  late Paddle paddle;
  late final Image? image;

  /// The girders, tiled up the level from the ground. See [_scaffoldShader].
  late final Paint _scaffoldPaint;
  final TeamDisplayPosition pos;
  late final BackgroundLayer bgLayer;
  bool _isInitialized = false;
  bool _bgLayerInitialized = false;

  /// Object pool for level objects
  late final LevelObjectPool _objectPool;

  /// Guard against re-entrant restartLevel() calls (e.g. ball touching two walls simultaneously)
  bool _isRestartingLevel = false;

  /// Tracks the most recently loaded level so `WorldController.currentLevel`
  /// can fall back to a concrete value if the level sequence is not yet set.
  RiseTogetherLevel? _lastLoadedLevel;

  WorldController get controller {
    if (!_isInitialized) {
      throw StateError(
        'WorldController not set for RiseTogetherWorld. '
        'Call setWorldController() after creating the world.',
      );
    }
    return _controller;
  }

  late WorldController _controller;

  /// Current team context providing consolidated team information
  TeamContext? _teamContext;

  /// Text component showing team name (stored for updates)
  TextComponent? _teamTextComponent;

  /// Proxy to get current level from controller
  RiseTogetherLevel get level => controller.currentLevel;

  /// Last level passed to loadLevel(); used as a safe fallback before controller's sequence is set.
  RiseTogetherLevel? get lastLoadedLevel => _lastLoadedLevel;

  RiseTogetherWorld({
    required this.pos,
    required RiseTogetherGameBase game,
    WorldController? controller,
    super.gravity,
  }) {
    gameRef = game;
    if (controller != null) {
      setWorldController(controller);
    }
    // Read from the cache rather than loaded in onLoad: loadLevel() can reach
    // _addBoundaries() before this world has mounted, and a late field
    // assigned in onLoad would still be uninitialized there. The game preloads
    // it before constructing any world.
    image = Flame.images.fromCache('assets/images/ground_floor.png');
    _scaffoldPaint = Paint()
      ..shader = _scaffoldShader(
        Flame.images.fromCache('assets/images/bg_scaffold.png'),
      );
    _objectPool = LevelObjectPool(this);
  }

  void setWorldController(WorldController controller) {
    _isInitialized = true;
    _controller = controller;
  }

  void setWorldCamera(
    CameraComponent camera, {
    RectangleComponent? cameraOverlay,
  }) {
    _worldCamera = camera;
    _viewportOverlay = cameraOverlay;
  }

  /// Resize what fills this world's viewport after the viewport itself was
  /// resized to [size]: the blackout rectangle and the starfield.
  void applyViewportSize(Vector2 size) {
    _viewportOverlay?.size = size;
    // parallax is late: unset until onLoad, which sizes it from the current
    // canvas anyway.
    if (!isLoaded) return;
    final backdrop = parallax;
    if (backdrop != null) {
      backdrop.size = size;
      // An explicitly sized ParallaxComponent ignores game resizes, and
      // setting its size alone does not re-lay-out the layers.
      backdrop.parallax?.resize(size);
    }
  }

  void blackout() {
    if (_viewportOverlay == null) {
      appLog.warning(
        'Cannot blackout: viewport overlay not set for world at position $pos',
      );
      return;
    }
    _viewportOverlay!.paint.blendMode = BlendMode.srcOver;
  }

  void reveal() {
    if (_viewportOverlay != null) {
      _viewportOverlay!.paint.blendMode = BlendMode.color;
    }
  }

  /// Whether this world is drawn through a camera at all.
  bool get hasWorldCamera => _worldCamera != null;

  /// The camera drawing this world.
  ///
  /// Throws when there is none; check [hasWorldCamera] first on any path that
  /// can run for the opponent's world under `ui.single_view_opponent`.
  CameraComponent get worldCamera {
    final camera = _worldCamera;
    if (camera == null) {
      throw StateError(
        'No camera for the world at position $pos. This world is never '
        'rendered -- guard the call with hasWorldCamera.',
      );
    }
    return camera;
  }

  /// Set the team context for this world
  void updateTeamContext(TeamContext teamContext) {
    _teamContext = teamContext;
    appLog.fine('Team context set for world: ${teamContext.toString()}');
    // Update any existing visual elements that depend on team colors
    _updateTeamColors();
  }

  /// Get current team context
  TeamContext? get teamContext => _teamContext;

  /// Update visual elements with current team colors
  void _updateTeamColors() {
    // Update team text component if it exists
    if (_teamTextComponent != null) {
      _teamTextComponent!.text = _getTeamDisplayText();
      _teamTextComponent!.textRenderer = TextPaint(
        style: TextStyle(
          color: _getTeamDisplayColor(),
          fontSize: 1,
          shadows: [
            Shadow(
              offset: Offset(0.05, 0.05),
              blurRadius: 0.8,
              color: Color.fromARGB(148, 0, 0, 0),
            ),
          ],
        ),
      );
      appLog.info(
        'Updated team text: "${_teamTextComponent!.text}" with team context: $_teamContext',
      );
    }
  }

  /// Get team display text based on team context
  String _getTeamDisplayText() {
    if (_teamContext != null) {
      return _teamContext!.isPlayerTeam ? 'You' : 'Opponent';
    }
    // Fallback to legacy behavior
    return pos == TeamDisplayPosition.left ? 'You' : 'Opponent';
  }

  /// Get team display color based on team context
  Color _getTeamDisplayColor() {
    if (_teamContext != null) {
      return _teamContext!.baseColor;
    }
    // Fallback to legacy behavior
    return pos == TeamDisplayPosition.left
        ? getTeamBaseColor(Team.a)
        : getTeamBaseColor(Team.b);
  }

  /// Bottom-left corner of the paddle bar. The y is the paddle's DOWN-facing
  /// face; [paddleEnd] carries the up-facing one.
  Vector2 paddleStart([double widthMultiplier = 1.0]) {
    return Vector2(
      -GameGeometry.paddleHalfWidth * widthMultiplier,
      GameGeometry.paddleBottomY,
    );
  }

  /// Top-right corner of the paddle bar. The y is the UP-facing face -- the
  /// surface the ball rests on.
  Vector2 paddleEnd([double widthMultiplier = 1.0]) {
    return Vector2(
      GameGeometry.paddleHalfWidth * widthMultiplier,
      GameGeometry.paddleTopY,
    );
  }

  Future<Paddle> buildPaddle({double widthMultiplier = 1.0}) async {
    paddle = Paddle(
      this,
      paddleStart(widthMultiplier),
      paddleEnd(widthMultiplier),
      baseWidthMultiplier: widthMultiplier,
    );
    appLog.info(
      '🔨 Building paddle with widthMultiplier=$widthMultiplier, start: ${paddleStart(widthMultiplier)}, end: ${paddleEnd(widthMultiplier)}',
    );

    add(paddle);
    await paddle.loaded;
    // The opponent's world in the single-view layout has no camera to follow
    // with. Its paddle still moves; nothing looks at it through a viewfinder.
    if (hasWorldCamera) {
      worldCamera.follow(paddle);
    }
    return paddle;
  }

  /// Ball centre at spawn: resting on the paddle's up-facing face.
  static Vector2 ballSpawnPosition() => Vector2(0.0, GameGeometry.ballSpawnY);

  Future<Ball> buildBall() async {
    ball = Ball(
      this,
      radius: GameGeometry.ballRadius,
      pos: ballSpawnPosition(),
    );
    add(ball);
    await ball.loaded;
    appLog.info('🔨 Building ball with radius: ${GameGeometry.ballRadius}');
    return ball;
  }

  @override
  void reset() {
    restartLevel(playerInitiated: false);
  }

  /// Within-level restart: put the ball and paddle back at rest in their start
  /// pose, and drop all held inputs for this team.
  ///
  /// Deliberately NOT a full [reset]: an obstacle's paddle-width effect is
  /// meant to last for the rest of the level, and is only dropped when the
  /// level changes (see [loadLevel]). The distinction lives in the components:
  /// [Paddle.clearMotion] restores the pose, [Paddle.reset] restores the pose
  /// *and* the width.
  void clearActions() {
    // Clear all player actions for this team when ball hits wall. Note this is
    // the network/stream half only, and it lands asynchronously -- clearMotion()
    // zeroes the local thrust immediately so the paddle cannot drift in the
    // meantime.
    gameRef.clearTeamActions(this);

    // Reset ball and paddle to starting positions (world components - reused)
    paddle.clearMotion();
    ball.clearMotion();
  }

  /// Kept as a named step for [WorldController.clearActions]; [clearActions]
  /// already repositions the ball, so this is idempotent.
  void resetBall() {
    ball.clearMotion();
  }

  Future<void> restartLevel({bool playerInitiated = true}) async {
    appLog.fine(
      'Restarting level with horizontal width: ${RiseTogetherLevel.horizontalWidth}.',
    );
    clearActions();
    resetBall();

    if (!playerInitiated) return;

    // Prevent re-entrancy: if a player-initiated countdown is already in progress,
    // ignore duplicate calls. This can happen when the ball simultaneously contacts
    // two fatal walls, or when the contact callback fires multiple times.
    if (_isRestartingLevel) {
      appLog.fine(
        'restartLevel() already in progress, ignoring duplicate call',
      );
      return;
    }
    _isRestartingLevel = true;

    // Check if this is the player's team
    final isPlayerTeam = _teamContext?.isPlayerTeam ?? false;
    final teamId = controller.team.teamId;

    // Always count the reset regardless of whether we're the player's team.
    // In headless/coordinator mode isPlayerTeam is always false, so counting
    // here ensures resets are tracked in all deployment modes.
    gameRef.tournamentManager.incrementTeamResets(teamId);

    // Only the player's own team sees a local countdown; the opponent team
    // resets and carries on. The authority also triggers the opponent team's
    // countdown on their devices.
    if (!isPlayerTeam) {
      if (gameRef.isCoordinator) {
        await gameRef.withTeamInputLocked(
          teamId,
          () => gameRef.broadcastTeamCountdownDirect(teamId, null),
        );
      }
      _isRestartingLevel = false;
      return;
    }

    // The engine keeps running -- the other team must continue playing.
    // Input is blocked while countdownSystem.isActive.
    gameRef.overlays.add('countdown');

    // Mirror each countdown step to this team's other players.
    void broadcastCurrentState() => gameRef.broadcastEvent(
      TeamCountdownState(
        teamId: teamId,
        stateIndex: gameRef.countdownSystem.currentState.index,
      ),
    );

    // Everything below runs under try/finally: _isRestartingLevel gates every
    // future restart, so leaving it set silently disables restarts.
    try {
      gameRef.countdownSystem.addListener(broadcastCurrentState);
      await gameRef.withTeamInputLocked(teamId, () async {
        await gameRef.countdownSystem.startCountdown();
        // Scoped to the run we just started, so a superseding countdown
        // releases us rather than stranding _isRestartingLevel = true forever.
        await gameRef.countdownSystem.runCompletion;
      });
    } finally {
      gameRef.countdownSystem.removeListener(broadcastCurrentState);
      gameRef.overlays.remove('countdown');
      _isRestartingLevel = false;
    }
  }

  /// Called when a level object is consumed (by authoritative coordinator)
  /// Notifies the game layer which handles network synchronization
  // @TODO: This is too coupled, better if it was event driven but for now
  // no time. But wee need to interact with the game so we can
  // make sure that participant devices also remove the object.
  void consumeLevelObject(int spawnId) {
    appLog.info(
      'Level object consumed: spawnId=$spawnId, teamId=${controller.team.teamId}',
    );

    // Notify the game layer through the controller callback
    controller.onLevelObjectConsumed?.call(controller.team.teamId, spawnId);
  }

  /// Remove a level object by its spawn ID (called on participants)
  /// Returns true if the object was found and removed
  bool removeLevelObjectBySpawnId(int spawnId) {
    // Find the object with matching spawnId
    final objects = children.query<LevelObject>();
    for (final obj in objects) {
      if (obj.spawnId == spawnId) {
        appLog.info(
          'Removing level object: spawnId=$spawnId, type=${obj.runtimeType}',
        );
        _objectPool.release(obj);
        return true;
      }
    }

    appLog.warning(
      'Could not find level object with spawnId=$spawnId to remove',
    );
    return false;
  }

  /// Tiles [scaffold] across the level in world space: one tile per
  /// level-width square, the bottom row standing on the ground (y = 0).
  ///
  /// The girders used to be the front parallax layer, scrolled from thrust at
  /// a fixed screen-pixel rate while the world moves at paddle speed times the
  /// camera zoom, which follows the viewport width. They matched the floor on
  /// one screen size only and slid off it everywhere else. Drawn in the world,
  /// they move exactly with it.
  static ImageShader _scaffoldShader(Image scaffold) {
    final tile = RiseTogetherLevel.horizontalWidth;
    final transform = Matrix4.identity()
      ..translateByDouble(-tile / 2, -tile, 0, 1)
      ..scaleByDouble(tile / scaffold.width, tile / scaffold.height, 1, 1);
    return ImageShader(
      scaffold,
      TileMode.repeated,
      TileMode.repeated,
      transform.storage,
      filterQuality: FilterQuality.medium,
    );
  }

  @override
  void render(Canvas canvas) {
    // Background first (before everything else): the girders, then the
    // gradient, which lightens over them as it did over the parallax layer.
    if (_bgLayerInitialized && bgLayer._ready) {
      canvas.save();
      canvas.drawRect(bgLayer.rect, _scaffoldPaint);
      canvas.drawRect(bgLayer.rect, bgLayer.paint);
      canvas.restore();
    }

    super.render(canvas);
  }

  /// Load a new level configuration
  /// Ball and paddle (world components) are reused and repositioned
  /// Walls and obstacles (level components) are recreated
  ///
  /// [rebuild] recreates the level even if it is already loaded, e.g. once
  /// the round's seed is known.
  Future<void> loadLevel(
    RiseTogetherLevel newLevel, {
    bool rebuild = false,
  }) async {
    appLog.info('Loading new level: ${newLevel.runtimeType}');

    // If the level is the same as the current one, just reset the ball and paddle
    if (!rebuild && _lastLoadedLevel == newLevel) {
      appLog.info(
        'Level ${newLevel.runtimeType} is already loaded, resetting ball and paddle',
      );
      clearActions();
      resetBall();
      return;
    }

    // Keep _lastLoadedLevel in sync so WorldController.currentLevel fallback is correct.
    _lastLoadedLevel = newLevel;

    // Initialize bgLayer on first load
    if (!_bgLayerInitialized) {
      bgLayer = BackgroundLayer(newLevel);
      _bgLayerInitialized = true;
    } else {
      // Update bgLayer for new level
      bgLayer.level = newLevel;
    }

    // Remove level components (walls, obstacles) - will be recreated
    removeWhere((component) => component is Wall || component is LevelObject);

    // Release all level objects back to pool
    _objectPool.releaseAll();

    // Reset temporary in-level effects (paddle width, control reversal) from
    // the previous level BEFORE repositioning. resetEffects() re-shapes the
    // paddle, and re-shaping calls cancelPendingTransforms() -- running it
    // afterwards used to throw away the repositioning done just above, and only
    // looked correct because updatePaddleShape() happens to re-apply the same
    // pose on its own.
    controller.resetEffects();

    // Reposition world components (ball, paddle) for new level. reset() is the
    // full "vanilla state" contract here (unlike the within-level restart in
    // clearActions), since a new level starts from the configured paddle width.
    //
    // paddle.startPosition is the bar's centre, which is also its body origin
    // -- the same value buildPaddle uses, so both paths agree.
    if (ball.isMounted) {
      ball.reset();
    }

    if (paddle.isMounted) {
      paddle.reset();
    }

    // Create new level components (walls, obstacles)
    final width = RiseTogetherLevel.horizontalWidth;
    // verticalHeight, NOT verticalMultiplier: the latter is a dimensionless
    // factor and only happens to equal the height while horizontalWidth == 1.
    final height = newLevel.verticalHeight;
    _addBoundaries(width, height);

    // Spawn level objects if configured
    final experimentSeed = gameRef.tournamentManager.currentTournamentSeed ?? 0;
    final spawnCfg = newLevel.spawnConfigForSeed(experimentSeed);
    if (spawnCfg != null) {
      _spawnLevelObjects(spawnCfg);
    }

    appLog.info(
      'Level loaded: ${newLevel.runtimeType} - world components reused, level components recreated',
    );
  }

  /// Spawn level objects using the spawn configuration
  void _spawnLevelObjects(LevelSpawnConfig config) {
    final spawned = config.generateSpawns(world: this, pool: _objectPool);

    appLog.info(
      'Spawning ${spawned.length} level objects with seed ${config.seed}',
    );

    // Assign deterministic spawn IDs based on spawn order
    for (int i = 0; i < spawned.length; i++) {
      final spawnedObject = spawned[i];
      spawnedObject.object.spawnId = i;
      appLog.info(
        'Adding ${spawnedObject.object.runtimeType} at position ${spawnedObject.position} with spawnId=$i',
      );
      add(spawnedObject.object);
    }
  }

  @override
  void update(double dt) {
    if (gameRef.isAuthoritativePhysics) {
      // Two passes so the common case (nothing consumed this frame) costs one
      // allocation-free scan. activeObjects is a live view, so the removal pass
      // must iterate a snapshot — release() mutates the underlying set.
      var hasConsumed = false;
      for (final obj in _objectPool.activeObjects) {
        if (obj.isConsumed) {
          hasConsumed = true;
          break;
        }
      }
      if (hasConsumed) {
        for (final obj in _objectPool.activeObjects.toList()) {
          if (obj.isConsumed) {
            appLog.info(
              'Removing consumed ${obj.runtimeType} from '
              'world at position ${obj.position}',
            );
            obj.beforeRemove?.call();
            _objectPool.release(obj);
          }
        }
      }
    }
    // Drive parallax from player thrust for authoritative-physics nodes only
    // (individual mode participants running LocalActionProvider). For follower
    // nodes (1v1 / joint participants), _interpolatePhysicsState() drives the
    // parallax via bitflags and must not be overwritten here.
    // Thrust-based (not ball velocity) avoids reversal when ball falls and
    // avoids jitter when the ball rolls across the paddle.
    if (controller.shouldUpdateParallax &&
        _bgLayerInitialized &&
        ball.isMounted) {
      final thrust = controller.actionStream.getCurrentThrust();
      final totalThrust = thrust.leftThrust + thrust.rightThrust;
      parallax?.parallax?.baseVelocity.setFrom(
        parallaxVelocityForThrust(
          totalThrust,
          appSettings.getDouble('physics.thrust_multiplier'),
        ),
      );
    }
    super.update(dt);
  }

  void _addBoundaries(double width, double height) {
    final List<Wall> walls = [
      // Bottom wall (ground) - fatal
      Wall(
        this,
        Vector2(-width / 2, 0),
        Vector2(width / 2, GameGeometry.groundDepth),
        isFatal: true,
        isLevelEnd: false,
        usePolygon: true,
        image: image,
        paint: Paint()
          ..color = const Color.fromARGB(255, 71, 71, 71)
          ..style = PaintingStyle.fill,
      ),
      // Right wall - fatal (no scraping!), not level end
      Wall(
        this,
        Vector2(width / 2, 0),
        Vector2(width / 2 + GameGeometry.wallThickness, -height),
        isFatal: true,
        isLevelEnd: false,
        paint: Paint()
          ..color = const Color.fromARGB(255, 0, 255, 51)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.01 * width,
      ),
      // Top wall - LEVEL END (not fatal!) — checkerboard rendered by Wall
      Wall(
        this,
        Vector2(width / 2, -height),
        Vector2(-width / 2, -height - GameGeometry.wallThickness),
        isFatal: false,
        isLevelEnd: true,
        paint: Paint()
          ..color = const Color.fromARGB(0, 0, 0, 0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.01 * width,
      ),
      // Left wall - fatal (no scraping!), not level end
      Wall(
        this,
        Vector2(-width / 2, -height),
        Vector2(-GameGeometry.wallThickness + -width / 2, 0),
        isFatal: true,
        isLevelEnd: false,
        paint: Paint()
          ..color = const Color.fromARGB(255, 204, 255, 0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.01 * width,
      ),
    ];
    appLog.fine('Adding boundaries with width: $width, height: $height.');
    for (final wall in walls) {
      appLog.fine('Adding wall: $wall');
    }
    addAll(walls);
    _teamTextComponent = TextComponent(
      text: _getTeamDisplayText(),
      anchor: Anchor.center,
      textRenderer: TextPaint(
        style: TextStyle(
          color: _getTeamDisplayColor(),
          fontSize: 1,
          shadows: [
            Shadow(
              offset: Offset(0.05, 0.05),
              blurRadius: 0.8,
              color: Color.fromARGB(148, 0, 0, 0),
            ),
          ],
        ),
      ),
      position: Vector2(0, GameGeometry.teamLabelY),
      size: Vector2(GameGeometry.teamLabelBoxWidth, 1),
      scale: Vector2.all(GameGeometry.teamLabelScale),
    );
    add(_teamTextComponent!);
  }

  @override
  Future<void> onLoad() async {
    children.register<Wall>();
    children.register<Ball>();
    children.register<Paddle>();
    children.register<LevelObject>();

    // Matches the camera viewport this world is drawn through: half the canvas
    // in the split view, the whole canvas in the single view. Sized wrong, the
    // starfield either tiles short of the viewport edge or scrolls at the
    // wrong apparent rate. Kept matched on resize by applyViewportSize.
    final parallaxSize = gameRef.viewportLayoutFor(pos).size;

    // The opponent's world has no camera in the single view, so its backdrop
    // would never be drawn -- skip the image layers rather than load them
    // to render nothing.
    final needsParallax =
        !(gameRef.singleViewOpponent && pos == TeamDisplayPosition.right);

    if (needsParallax) {
      parallax = await gameRef.loadParallaxComponent(
        [
          ParallaxImageData('assets/images/stars_0.png'),
          ParallaxImageData('assets/images/stars_1.png'),
          ParallaxImageData('assets/images/stars_2.png'),
          // The girders are drawn in the world instead; see _scaffoldShader.
        ],
        baseVelocity: Vector2(0, 0),
        repeat: ImageRepeat.repeatY,
        fill: LayerFill.width,
        size: parallaxSize,
        velocityMultiplierDelta: Vector2(0, 5),
      );
      worldCamera.backdrop.add(parallax!);
    } else {
      parallax = null;
    }

    // Note: bgLayer is initialized when loadLevel() is called during game configuration,
    // since it needs access to controller.currentLevel.
    // Boundaries and level objects are also NOT created here to avoid wasteful duplication.
  }
}
