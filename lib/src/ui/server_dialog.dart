import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rise_together_game/src/online/online_config.dart';

/// Edits the lobby server. Pops the new setting value: the typed address, or
/// '' for this build's default; null when cancelled.
class ServerDialog extends StatefulWidget {
  const ServerDialog({
    super.key,
    required this.initial,
    required this.defaultUrl,
  });

  final String initial;
  final Uri? defaultUrl;

  @override
  State<ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<ServerDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid =>
      _controller.text.trim().isEmpty ||
      OnlineConfig.parse(_controller.text) != null;

  @override
  Widget build(BuildContext context) {
    final defaultUrl = widget.defaultUrl;
    return AlertDialog(
      title: Text('settings.server.title'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: defaultUrl?.toString() ?? 'https://',
              helperText: defaultUrl == null
                  ? 'settings.server.defaultNone'.tr()
                  : 'settings.server.defaultIs'.tr(
                      args: [defaultUrl.toString()],
                    ),
              helperMaxLines: 3,
              errorText: _valid ? null : 'settings.server.invalid'.tr(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (kIsWeb) ...[
            const SizedBox(height: 12),
            Text(
              'settings.server.webHint'.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: Text('settings.server.useDefault'.tr()),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('settings.colors.cancel'.tr()),
        ),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.pop(context, _controller.text.trim())
              : null,
          child: Text('settings.server.save'.tr()),
        ),
      ],
    );
  }
}
