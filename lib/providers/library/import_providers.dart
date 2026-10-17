import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/library/link_classifier.dart';
import 'package:medito/services/library/share_intake.dart';

/// The system pickers, behind an interface so tests need no platform.
abstract interface class ImportPickers {
  /// Audio files the user chose, or null if they backed out.
  Future<List<PickedFile>?> pickAudioFiles();

  /// A folder's path, or null.
  Future<String?> pickFolder();
}

class SystemImportPickers implements ImportPickers {
  const SystemImportPickers();

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
  Future<String?> pickFolder() => FilePicker.getDirectoryPath();
}

final importPickersProvider = Provider<ImportPickers>(
  (ref) => const SystemImportPickers(),
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
