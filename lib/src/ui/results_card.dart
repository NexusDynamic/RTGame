import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// End-of-round summary shown over the paused game.
class ResultsCard extends StatelessWidget {
  const ResultsCard({
    super.key,
    required this.title,
    required this.rows,
    required this.onBackToMenu,
    this.onPlayAgain,
    this.highlight,
  });

  final String title;

  /// A line called out under the title, e.g. "New personal best!".
  final String? highlight;

  /// Label / value pairs.
  final List<(String, String)> rows;

  /// Null hides the button (e.g. an online game only the host can restart).
  final VoidCallback? onPlayAgain;
  final VoidCallback onBackToMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: theme.textTheme.headlineMedium),
                  if (highlight != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      highlight!,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  for (final (label, value) in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(label, style: theme.textTheme.bodyLarge),
                          Text(value, style: theme.textTheme.titleLarge),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  if (onPlayAgain != null)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onPlayAgain,
                        child: Text('results.playAgain'.tr()),
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onBackToMenu,
                      child: Text('results.backToMenu'.tr()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
