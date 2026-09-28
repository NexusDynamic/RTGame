import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:rise_together_game/src/game/rise_together_game.dart';
import 'package:rise_together_game/src/game/countdown_system.dart';
import 'package:rise_together_game/src/ui/overlay.dart';

/// Overlay that displays countdown text (3, 2, 1, GO!)
class CountdownOverlay extends StatefulWidget implements RiseTogetherOverlay {
  static const String overlayID = 'countdown';
  final RiseTogetherGameBase game;

  const CountdownOverlay(this.game, {super.key});

  @override
  State<CountdownOverlay> createState() => _CountdownOverlayState();
}

class _CountdownOverlayState extends State<CountdownOverlay> {
  @override
  void initState() {
    super.initState();
    // Listen to countdown state changes
    widget.game.countdownSystem.addListener(_onCountdownChange);
  }

  @override
  void dispose() {
    widget.game.countdownSystem.removeListener(_onCountdownChange);
    super.dispose();
  }

  void _onCountdownChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final countdownText = widget.game.countdownSystem.getDisplayText();
    final isMessageState =
        widget.game.countdownSystem.currentState == CountdownState.message;

    // Don't show anything if countdown is not active
    if (countdownText.isEmpty) {
      return const SizedBox.shrink();
    }

    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Container(
          padding: isMessageState
              ? const EdgeInsets.symmetric(horizontal: 80, vertical: 50)
              : const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
          decoration: BoxDecoration(
            color: const Color.fromARGB(200, 0, 0, 0),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color.fromARGB(150, 0, 0, 0),
                spreadRadius: 5,
                blurRadius: 15,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            _getLocalizedCountdownText(countdownText),
            style: TextStyle(
              color: isMessageState
                  ? const Color.fromARGB(
                      255,
                      255,
                      200,
                      0,
                    ) // Orange/gold for level message
                  : countdownText == 'GO!'
                  ? const Color.fromARGB(255, 0, 255, 100)
                  : const Color.fromARGB(255, 255, 255, 255),
              fontSize: isMessageState ? 48 : 120, // Smaller text for message
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(
                  offset: const Offset(0, 0),
                  blurRadius: 20,
                  color: isMessageState
                      ? const Color.fromARGB(200, 255, 200, 0)
                      : countdownText == 'GO!'
                      ? const Color.fromARGB(200, 0, 255, 100)
                      : const Color.fromARGB(200, 255, 255, 255),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  String _getLocalizedCountdownText(String text) {
    switch (text) {
      case 'GO!':
        return 'countdown.go'.tr();
      case '3':
        return 'countdown.three'.tr();
      case '2':
        return 'countdown.two'.tr();
      case '1':
        return 'countdown.one'.tr();
      default:
        return text;
    }
  }
}
