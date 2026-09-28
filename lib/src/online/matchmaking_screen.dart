import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rise_together_lobby/protocol.dart';
import 'package:rise_together_game/src/levels/custom_level.dart';
import 'package:rise_together_game/src/online/custom_levels_badge.dart';
import 'package:rise_together_game/src/online/lobby_client.dart';
import 'package:rise_together_game/src/online/matchmaking_controller.dart';
import 'package:rise_together_game/src/online/online_game_screen.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';
import 'package:webrtc_coordinator_flutter/webrtc_coordinator_flutter.dart'
    show flutterWebrtcAdapterFactory;

/// Shows matchmaking progress, then hands over to the game.
class MatchmakingScreen extends StatefulWidget {
  const MatchmakingScreen({
    super.key,
    required this.lobbyUrl,
    required this.request,
    this.customLevels,
  });

  final Uri lobbyUrl;
  final ClientMessage request;

  /// This player's levels, for a custom-levels request.
  final CustomLevelPack? customLevels;

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends State<MatchmakingScreen>
    with AppSettings {
  late final MatchmakingController _controller = MatchmakingController(
    lobby: LobbyClient(widget.lobbyUrl),
    adapterFactory: flutterWebrtcAdapterFactory,
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChange);
    unawaited(
      _controller.start(
        request: widget.request,
        nickname: appSettings.getString('player.nickname'),
        roundDurationSeconds: appSettings.getDouble('game.round_duration'),
        customLevels: widget.customLevels,
      ),
    );
  }

  void _onChange() {
    final state = _controller.state;
    if (state is MatchReady && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => OnlineGameScreen(session: state.session),
        ),
      );
      return;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    // Releases the lobby socket and any half-open session; a session that
    // was handed to the game is left alone.
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = _controller.state;
    final failed = state is MatchmakingFailed;

    return Scaffold(
      appBar: AppBar(title: Text('online.title'.tr())),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!failed) const CircularProgressIndicator(),
                if (failed)
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                const SizedBox(height: 24),
                if (_isCustom(state)) ...[
                  const CustomLevelsBadge(),
                  const SizedBox(height: 8),
                  Text(
                    'online.customLevelsNotice'.tr(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                ],
                ..._describe(state, theme),
                const SizedBox(height: 32),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    failed ? 'online.back'.tr() : 'online.cancel'.tr(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static bool _isCustom(MatchmakingState state) => switch (state) {
    Gathering(:final custom) || ConnectingToPlayers(:final custom) => custom,
    _ => false,
  };

  List<Widget> _describe(MatchmakingState state, ThemeData theme) {
    Widget line(String text) => Text(
      text,
      textAlign: TextAlign.center,
      style: theme.textTheme.titleMedium,
    );

    return switch (state) {
      Admitting() => [line('online.status.admitting'.tr())],
      Gathering(:final joined, :final players, :final code?) => [
        Text('online.status.roomCode'.tr(), style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        SelectableText(
          code,
          style: theme.textTheme.displayMedium?.copyWith(
            letterSpacing: 8,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy),
          tooltip: MaterialLocalizations.of(context).copyButtonLabel,
          onPressed: () => Clipboard.setData(ClipboardData(text: code)),
        ),
        const SizedBox(height: 8),
        Text(
          'online.status.shareCode'.tr(
            args: [players.toString(), players.toString()],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        line('$joined / $players'),
      ],
      Gathering(:final joined, :final players) => [
        line(
          'online.status.searching'.tr(
            args: [joined.toString(), players.toString()],
          ),
        ),
      ],
      ConnectingToPlayers(:final host) => [
        line(
          host ? 'online.status.hosting'.tr() : 'online.status.connecting'.tr(),
        ),
      ],
      MatchReady() => [line('online.status.connecting'.tr())],
      MatchmakingFailed(:final reason) => [
        line('online.failure.${reason.name}'.tr()),
      ],
    };
  }
}
