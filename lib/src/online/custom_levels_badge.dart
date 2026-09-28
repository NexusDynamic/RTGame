import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Marks a match played on player-made levels rather than the built-in ones.
class CustomLevelsBadge extends StatelessWidget {
  const CustomLevelsBadge({super.key, this.dense = false});

  /// Smaller, for in-game use.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'online.customLevels'.tr(),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 12,
          vertical: dense ? 2 : 6,
        ),
        decoration: BoxDecoration(
          color: colors.tertiaryContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.terrain_outlined,
              size: dense ? 14 : 18,
              color: colors.onTertiaryContainer,
            ),
            SizedBox(width: dense ? 4 : 6),
            Text(
              'online.customBadge'.tr(),
              style: TextStyle(
                color: colors.onTertiaryContainer,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                fontSize: dense ? 11 : 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
