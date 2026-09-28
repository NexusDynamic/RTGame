import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rise_together_lobby/protocol.dart';
import 'package:rise_together_game/src/editor/level_library_screen.dart';
import 'package:rise_together_game/src/levels/level_library.dart';
import 'package:rise_together_game/src/online/matchmaking_screen.dart';

/// Choose how to play online: quick match, a private room, or a code.
class OnlineMenuScreen extends StatefulWidget {
  const OnlineMenuScreen({super.key, required this.lobbyUrl});

  final Uri lobbyUrl;

  @override
  State<OnlineMenuScreen> createState() => _OnlineMenuScreenState();
}

class _OnlineMenuScreenState extends State<OnlineMenuScreen> {
  LobbyMode _mode = LobbyMode.versus;
  int _players = 2;
  final _code = TextEditingController();

  /// Levels to play on instead of the built-in ones, if the player chose some.
  CustomSelection? _custom;

  Future<void> _toggleCustom(bool on) async {
    if (!on) {
      setState(() => _custom = null);
      return;
    }
    final selection = await pickCustomLevels(context);
    if (selection == null || selection.pack == null) return;
    setState(() => _custom = selection);
  }

  /// Versus needs even teams; co-op takes any size.
  List<int> get _sizes => _mode == LobbyMode.versus ? [2, 4] : [2, 3, 4];

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _go(ClientMessage request) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MatchmakingScreen(
        lobbyUrl: widget.lobbyUrl,
        request: request,
        customLevels: request is JoinRoom ? null : _custom?.pack,
      ),
    ),
  );

  String _sizeLabel(int size) =>
      _mode == LobbyMode.versus ? 'online.teamSizes.${size}v'.tr() : '$size';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final codeValid = isValidRoomCode(_code.text);
    return Scaffold(
      appBar: AppBar(title: Text('online.title'.tr())),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SegmentedButton<LobbyMode>(
                segments: [
                  for (final mode in LobbyMode.values)
                    ButtonSegment(
                      value: mode,
                      label: Text('online.mode.${mode.name}'.tr()),
                      icon: Icon(
                        mode == LobbyMode.coop ? Icons.handshake : Icons.bolt,
                      ),
                    ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() {
                  _mode = s.single;
                  if (!_sizes.contains(_players)) _players = _sizes.first;
                }),
              ),
              const SizedBox(height: 8),
              Text(
                'online.modeHelp.${_mode.name}'.tr(),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              Text('online.players'.tr(), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final size in _sizes)
                    ChoiceChip(
                      label: Text(_sizeLabel(size)),
                      selected: _players == size,
                      onSelected: (_) => setState(() => _players = size),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.terrain_outlined),
                title: Text('online.customLevels'.tr()),
                subtitle: Text(
                  _custom == null
                      ? 'online.customLevelsHelp'.tr()
                      : 'online.customLevelsChosen'.tr(
                          args: [_custom!.name, '${_custom!.levels.length}'],
                        ),
                ),
                value: _custom != null,
                onChanged: _toggleCustom,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: const Icon(Icons.travel_explore),
                label: Text('online.quickMatch'.tr()),
                onPressed: () => _go(
                  QuickMatch(
                    mode: _mode,
                    players: _players,
                    custom: _custom != null,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                child: Text(
                  _custom == null
                      ? 'online.quickMatchHelp'.tr()
                      : 'online.quickMatchCustomHelp'.tr(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.lock),
                label: Text('online.createRoom'.tr()),
                onPressed: () => _go(
                  CreateRoom(
                    mode: _mode,
                    players: _players,
                    custom: _custom != null,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'online.createRoomHelp'.tr(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const Divider(height: 48),
              Text('online.haveCode'.tr(), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: roomCodeLength,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        hintText: 'online.codeHint'.tr(),
                        counterText: '',
                      ),
                      inputFormatters: [
                        // Upper-case, and only characters a code can contain.
                        TextInputFormatter.withFunction((_, value) {
                          final text = value.text
                              .toUpperCase()
                              .split('')
                              .where(roomCodeAlphabet.contains)
                              .join();
                          // Dropping characters shortens the text, so the
                          // cursor must move with it or it points past the end.
                          return TextEditingValue(
                            text: text,
                            selection: TextSelection.collapsed(
                              offset: text.length,
                            ),
                          );
                        }),
                      ],
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) {
                        if (codeValid) _go(JoinRoom(code: _code.text));
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonal(
                    onPressed: codeValid
                        ? () => _go(JoinRoom(code: _code.text))
                        : null,
                    child: Text('online.join'.tr()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
