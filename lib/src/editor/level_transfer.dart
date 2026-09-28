import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rise_together_game/src/levels/custom_level.dart';
import 'package:rise_together_game/src/services/app_logging.dart';

/// Moving levels in and out of the game: clipboard or a file, on every
/// platform including the web (where saving downloads the file).
abstract final class LevelTransfer {
  static const extension = 'json';

  static AppLogger get _log => AppLogger.instance;

  /// Offer to copy or save [levels]. [fileName] has no extension.
  static Future<void> export(
    BuildContext context,
    List<CustomLevel> levels, {
    required String fileName,
  }) async {
    final text = CustomLevelFile.encode(levels);
    final messenger = ScaffoldMessenger.of(context);
    final choice = await _choose(
      context,
      title: 'library.exportTitle'.tr(),
      copyLabel: 'library.copy'.tr(),
      fileLabel: 'library.saveFile'.tr(),
    );
    if (choice == null) return;
    try {
      if (choice == _Via.clipboard) {
        await Clipboard.setData(ClipboardData(text: text));
        messenger.showSnackBar(SnackBar(content: Text('library.copied'.tr())));
      } else {
        final saved = await FilePicker.saveFile(
          fileName: '${_safeFileName(fileName)}.rtlevels.$extension',
          bytes: utf8.encode(text),
          mimeType: 'application/json',
        );
        if (saved != null) {
          messenger.showSnackBar(
            SnackBar(content: Text('library.savedFile'.tr())),
          );
        }
      }
    } on Exception catch (e) {
      _log.warning('Export failed: $e');
      messenger.showSnackBar(
        SnackBar(content: Text('library.exportFailed'.tr())),
      );
    }
  }

  /// Ask for levels from the clipboard or a file. Null if the player
  /// cancelled; shows an error and returns null if the data is not valid.
  static Future<List<CustomLevel>?> import(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final choice = await _choose(
      context,
      title: 'library.importTitle'.tr(),
      copyLabel: 'library.paste'.tr(),
      fileLabel: 'library.openFile'.tr(),
    );
    if (choice == null) return null;

    String? text;
    try {
      text = choice == _Via.clipboard
          ? (await Clipboard.getData(Clipboard.kTextPlain))?.text
          : await _readFile();
    } on Exception catch (e) {
      _log.warning('Import failed: $e');
    }
    if (text == null) {
      if (choice == _Via.clipboard) {
        messenger.showSnackBar(
          SnackBar(content: Text('library.importInvalid'.tr())),
        );
      }
      return null;
    }

    final levels = CustomLevelFile.decode(text);
    if (levels == null) {
      messenger.showSnackBar(
        SnackBar(content: Text('library.importInvalid'.tr())),
      );
    }
    return levels;
  }

  /// The picked file's text, or null if cancelled, too big or not UTF-8.
  static Future<String?> _readFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const [extension],
    );
    if (file == null) return null;
    // UTF-8 is at most 4 bytes a character; refuse before reading it all.
    final length = await file.length();
    if (length != null && length > CustomLevelLimits.maxFileChars * 4) {
      return null;
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > CustomLevelLimits.maxFileChars * 4) return null;
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return null;
    }
  }

  static String _safeFileName(String name) {
    final cleaned = name
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return cleaned.isEmpty ? 'levels' : cleaned;
  }

  static Future<_Via?> _choose(
    BuildContext context, {
    required String title,
    required String copyLabel,
    required String fileLabel,
  }) => showModalBottomSheet<_Via>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(title)),
          ListTile(
            leading: const Icon(Icons.content_paste),
            title: Text(copyLabel),
            onTap: () => Navigator.pop(context, _Via.clipboard),
          ),
          ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(fileLabel),
            onTap: () => Navigator.pop(context, _Via.file),
          ),
        ],
      ),
    ),
  );
}

enum _Via { clipboard, file }
