import 'package:rise_together_game/src/game/rise_together_game.dart';

/// The game base with nothing but the abstract hook filled in, for tests that
/// never mount or render it.
class TestGame extends RiseTogetherGameBase {
  TestGame({required super.actionManager});

  @override
  void roundComplete() {}

  @override
  // ignore: unnecessary_overrides -- Resetable marks reset() must-override.
  Future<void> reset() => super.reset();
}
