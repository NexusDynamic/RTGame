import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Leaves the current game after asking the player to confirm.
class QuitButton extends StatelessWidget {
  const QuitButton({
    super.key,
    this.onQuit,
    this.leaveScreen = true,
    this.message,
  });

  /// Replaces the default "progress will be lost" warning.
  final String? message;

  /// Runs before the screen is popped, e.g. to leave an online session.
  final Future<void> Function()? onQuit;

  /// False keeps the screen, e.g. to show the results of an untimed run.
  final bool leaveScreen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: IconButton.filledTonal(
      tooltip: 'game.quit'.tr(),
      icon: const Icon(Icons.close),
      onPressed: () async {
        final navigator = Navigator.of(context);
        final leave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('game.quitTitle'.tr()),
            content: Text(message ?? 'game.quitMessage'.tr()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('game.stay'.tr()),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('game.leave'.tr()),
              ),
            ],
          ),
        );
        if (leave != true) return;
        await onQuit?.call();
        if (leaveScreen) navigator.pop();
      },
    ),
  );
}
