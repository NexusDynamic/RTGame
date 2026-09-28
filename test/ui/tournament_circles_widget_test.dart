import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/ui/tournament_circles_widget.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('TournamentCirclesWidget', () {
    testWidgets('renders exactly totalRounds circles', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TournamentCirclesWidget(
            totalRounds: 3,
            team0Wins: 0,
            team1Wins: 0,
          ),
        ),
      );
      // Each circle is a Container with BoxDecoration; count the Containers
      // inside the Row (excluding the Row's own Container wrapper if any).
      final containers = tester.widgetList<Container>(find.byType(Container));
      // totalRounds circles = 3 Container widgets (one per circle)
      expect(containers.length, equals(3));
    });

    testWidgets('renders 5 circles for totalRounds=5', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TournamentCirclesWidget(
            totalRounds: 5,
            team0Wins: 0,
            team1Wins: 0,
          ),
        ),
      );
      expect(
        tester.widgetList<Container>(find.byType(Container)).length,
        equals(5),
      );
    });

    testWidgets('team0 wins fill from the left', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TournamentCirclesWidget(
            totalRounds: 3,
            team0Wins: 2,
            team1Wins: 0,
            team0Color: Color(0xFF0000FF),
            team1Color: Color(0xFFFF0000),
          ),
        ),
      );
      await tester.pump();

      // Find all BoxDecorations and collect their fill colours
      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .toList();
      final fills = containers
          .map((c) => (c.decoration as BoxDecoration?)?.color)
          .toList();

      // First 2 should be blue (team0Color), last 1 should be transparent
      expect(fills[0], equals(const Color(0xFF0000FF)));
      expect(fills[1], equals(const Color(0xFF0000FF)));
      expect(fills[2], equals(Colors.transparent));
    });

    testWidgets('team1 wins fill from the right', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TournamentCirclesWidget(
            totalRounds: 3,
            team0Wins: 0,
            team1Wins: 2,
            team0Color: Color(0xFF0000FF),
            team1Color: Color(0xFFFF0000),
          ),
        ),
      );
      await tester.pump();

      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .toList();
      final fills = containers
          .map((c) => (c.decoration as BoxDecoration?)?.color)
          .toList();

      // Last 2 should be red (team1Color), first 1 should be transparent
      expect(fills[0], equals(Colors.transparent));
      expect(fills[1], equals(const Color(0xFFFF0000)));
      expect(fills[2], equals(const Color(0xFFFF0000)));
    });

    testWidgets('no wins leaves all circles unfilled (transparent)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const TournamentCirclesWidget(
            totalRounds: 3,
            team0Wins: 0,
            team1Wins: 0,
          ),
        ),
      );
      await tester.pump();

      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .toList();
      for (final c in containers) {
        final fill = (c.decoration as BoxDecoration?)?.color;
        expect(fill, equals(Colors.transparent));
      }
    });

    testWidgets('split wins show correct left and right fills', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TournamentCirclesWidget(
            totalRounds: 4,
            team0Wins: 1,
            team1Wins: 1,
            team0Color: Color(0xFF0000FF),
            team1Color: Color(0xFFFF0000),
          ),
        ),
      );
      await tester.pump();

      final fills = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => (c.decoration as BoxDecoration?)?.color)
          .toList();

      // index 0: blue (team0), index 3: red (team1), indices 1-2: transparent
      expect(fills[0], equals(const Color(0xFF0000FF)));
      expect(fills[1], equals(Colors.transparent));
      expect(fills[2], equals(Colors.transparent));
      expect(fills[3], equals(const Color(0xFFFF0000)));
    });
  });
}
