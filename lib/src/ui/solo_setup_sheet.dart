import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:rise_together_game/src/editor/level_library_screen.dart';
import 'package:rise_together_game/src/game/level_sequence.dart';
import 'package:rise_together_game/src/game/rise_together_game.dart'
    show TimeProvider;
import 'package:rise_together_game/src/levels/solo_progress.dart';
import 'package:rise_together_game/src/ui/solo_game_screen.dart';

/// Choose how to play solo: timed or not, and where to start. Returns the
/// game screen to open, or null if the player backed out.
Future<SoloGameScreen?> showSoloSetupSheet(BuildContext context) =>
    showModalBottomSheet<SoloGameScreen>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SoloSetupSheet(),
    );

class _SoloSetupSheet extends StatefulWidget {
  const _SoloSetupSheet();

  @override
  State<_SoloSetupSheet> createState() => _SoloSetupSheetState();
}

class _SoloSetupSheetState extends State<_SoloSetupSheet> {
  final _progress = SoloProgress();
  bool _timed = true;
  late int _start = _progress.startableLevelCount - 1;

  Future<void> _playCustom() async {
    final navigator = Navigator.of(context);
    final selection = await pickCustomLevels(context);
    if (selection == null) return;
    navigator.pop(
      SoloGameScreen(
        timed: _timed,
        sequence: LevelSequence.custom(selection.levels),
        customRunKey: _timed ? null : SoloProgress.customRunKey(selection.key),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final startable = _progress.startableLevelCount;
    final best = _timed
        ? null
        : _progress.bestTime(SoloProgress.builtInRunKey(_start));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('solo.title'.tr(), style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.timer_outlined),
                  label: Text('solo.timed'.tr()),
                ),
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.all_inclusive),
                  label: Text('solo.untimed'.tr()),
                ),
              ],
              selected: {_timed},
              onSelectionChanged: (v) => setState(() => _timed = v.single),
            ),
            const SizedBox(height: 8),
            Text(
              _timed ? 'solo.timedHelp'.tr() : 'solo.untimedHelp'.tr(),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text('solo.startLevel'.tr(), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < SoloProgress.builtInLevelCount; i++)
                  ChoiceChip(
                    avatar: i < startable
                        ? null
                        : const Icon(Icons.lock, size: 16),
                    label: Text('${i + 1}'),
                    selected: _start == i,
                    onSelected: i < startable
                        ? (_) => setState(() => _start = i)
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('solo.unlockHelp'.tr(), style: theme.textTheme.bodySmall),
            if (best != null) ...[
              const SizedBox(height: 8),
              Text(
                'solo.bestTime'.tr(
                  args: [TimeProvider.formatSeconds(best.floor())],
                ),
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: Text('solo.play'.tr()),
              onPressed: () => Navigator.pop(
                context,
                SoloGameScreen(timed: _timed, startLevelIndex: _start),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.terrain_outlined),
              label: Text('solo.playCustom'.tr()),
              onPressed: _playCustom,
            ),
          ],
        ),
      ),
    );
  }
}
