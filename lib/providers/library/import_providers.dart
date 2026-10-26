import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/services/library/folder_import.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/library/link_classifier.dart';
import 'package:medito/services/library/share_intake.dart';

/// The system pickers, behind an interface so tests need no platform.
abstract interface class ImportPickers {
  /// Audio files the user chose, or null if they backed out.
  Future<List<PickedFile>?> pickAudioFiles();

  /// A folder, or null if the user backed out or cancelled. On Android its
  /// audio arrives already copied (see [FolderImporter]), with [onProgress]
  /// reporting the copy; elsewhere only its path.
  Future<PickedFolder?> pickFolder({void Function(FolderProgress)? onProgress});

  /// Stops a folder pick or copy in progress.
  Future<void> cancelFolderImport();

  /// Removes what a folder import staged and nothing took.
  Future<void> discardFolderImport();
}

class SystemImportPickers implements ImportPickers {
  SystemImportPickers({FolderImporter? folders, bool? isAndroid})
    : _folders = folders,
      _isAndroid = isAndroid ?? Platform.isAndroid;

  FolderImporter? _folders;
  final bool _isAndroid;

  /// Created on first use, so only a device that imports a folder this way
  /// ever opens the channel.
  FolderImporter get _folderImporter => _folders ??= ChannelFolderImporter();

  @override
  Future<List<PickedFile>?> pickAudioFiles() async {
    final result = await FilePicker.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    if (result == null) return null;
    return [
      for (final file in result.files)
        if (file.path != null)
          PickedFile(path: file.path!, name: file.name, sizeBytes: file.size),
    ];
  }

  @override
  Future<PickedFolder?> pickFolder({
    void Function(FolderProgress)? onProgress,
  }) async {
    if (_isAndroid) {
      return _folderImporter.importFolder(onProgress: onProgress);
    }
    // iOS and desktops can still read a folder by its path.
    final path = await FilePicker.getDirectoryPath();
    return path == null ? null : PickedFolder.path(path);
  }

  @override
  Future<void> cancelFolderImport() async {
    if (_isAndroid) await _folderImporter.cancel();
  }

  @override
  Future<void> discardFolderImport() async {
    if (_isAndroid) await _folderImporter.discard();
  }
}

final importPickersProvider = Provider<ImportPickers>(
  (ref) => SystemImportPickers(),
);

/// Reads a link from the clipboard if there is one worth offering. The
/// check for text does not read it (and so does not trigger iOS's paste
/// prompt); only text that is there is read, and only to look for a link.
typedef ClipboardLinkReader = Future<String?> Function();

Future<String?> readClipboardLink() async {
  try {
    if (!await Clipboard.hasStrings()) return null;
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || !looksImportable(text)) return null;
    return firstLinkIn(text.trim()) ?? text.trim();
  } catch (_) {
    return null;
  }
}

final clipboardLinkReaderProvider = Provider<ClipboardLinkReader>(
  (ref) => readClipboardLink,
);

/// Links and files shared into the app from other apps.
final shareIntakeProvider = Provider<ShareIntake>(
  (ref) => PlatformShareIntake(),
);
