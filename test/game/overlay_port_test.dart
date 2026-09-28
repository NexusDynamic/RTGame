import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/overlay_port.dart';

/// The port replaces eleven `if (!isHeadlessMode)` guards that each expressed
/// the same fact — the coordinator has no widgets — at a different call site.
void main() {
  group('NoOverlayPort', () {
    const port = NoOverlayPort();

    test('accepts and discards everything', () {
      // The headless coordinator holds this. Calls must be inert, not errors:
      // the shared game base issues them unconditionally now.
      expect(() => port.add('inGameUI'), returnsNormally);
      expect(() => port.remove('inGameUI'), returnsNormally);
    });

    test('reports nothing as active', () {
      // Consistent: an overlay that was never shown is not showing. Code that
      // reads `if (!isActive(x)) add(x)` therefore behaves sanely.
      port.add('countdown');
      expect(port.isActive('countdown'), isFalse);
    });

    test('remove on something never added is fine', () {
      expect(() => port.remove('never_added'), returnsNormally);
    });
  });

  group('FlameOverlayPort', () {
    late Set<String> active;
    late FlameOverlayPort port;

    setUp(() {
      active = <String>{};
      port = FlameOverlayPort(
        addOverlay: active.add,
        removeOverlay: active.remove,
        overlayIsActive: active.contains,
      );
    });

    test('forwards add, remove and isActive', () {
      port.add('inGameUI');
      expect(port.isActive('inGameUI'), isTrue);
      expect(active, contains('inGameUI'));

      port.remove('inGameUI');
      expect(port.isActive('inGameUI'), isFalse);
    });

    test('tracks several overlays independently', () {
      port.add('countdown');
      port.add('inGameUI');
      port.remove('countdown');

      expect(port.isActive('countdown'), isFalse);
      expect(port.isActive('inGameUI'), isTrue);
    });

    test('the remove-then-add rebuild bounce leaves it active', () {
      // _updateTeamContexts does this to force the in-game UI to rebuild after
      // team assignment changes.
      port.add('inGameUI');
      port.remove('inGameUI');
      port.add('inGameUI');

      expect(port.isActive('inGameUI'), isTrue);
    });
  });

  group('substitutability', () {
    test('both satisfy the same interface', () {
      // Which one a node holds is the only difference between "shows UI" and
      // "does not" — there is no role check left at the call sites.
      final ports = <OverlayPort>[
        const NoOverlayPort(),
        FlameOverlayPort(
          addOverlay: (_) {},
          removeOverlay: (_) {},
          overlayIsActive: (_) => false,
        ),
      ];

      for (final port in ports) {
        expect(() {
          port.add('x');
          port.isActive('x');
          port.remove('x');
        }, returnsNormally);
      }
    });
  });
}
