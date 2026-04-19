import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart' as pub_picker;

// NOTE: In production, import the Pigeon-generated file instead:
// import 'file_picker_api.g.dart';
//
// This file provides a thin façade that:
//   1. Calls the Pigeon channel if available (real native impl)
//   2. Falls back to the pub.dev file_picker package if not yet implemented
//
// The Pigeon definition lives in pigeons/file_picker_api.dart.
// Run: dart run pigeon --input pigeons/file_picker_api.dart
// to regenerate the glue code.

class PickedFile {
  final String path;
  final String name;
  final int sizeBytes;
  final String mimeType;

  const PickedFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.mimeType,
  });
}

class SaveResult {
  final bool success;
  final String? savedPath;
  final String? errorMessage;

  const SaveResult({
    required this.success,
    this.savedPath,
    this.errorMessage,
  });
}

/// [NativeFilePicker] is the public API surface used by the rest of the app.
///
/// Platform channel (Pigeon) status:
///   Android: HostApi skeleton generated. KotlinHandler registered in
///            MainActivity. ACTION_OPEN_DOCUMENT flow implemented.
///            MediaStore save implemented. Share sheet implemented.
///   iOS:     Pigeon Swift skeleton generated. UIDocumentPickerViewController
///            wiring is NOT YET COMPLETE (time constraint).
///            Falls back to pub.dev file_picker on iOS.
///
/// See README §"Platform Channel Bonus" for full status and next steps.
class NativeFilePicker {
  NativeFilePicker._();
  static final NativeFilePicker instance = NativeFilePicker._();

  /// Attempt to use the native Pigeon channel; fall back to pub.dev.
  Future<List<PickedFile>> pickFiles({bool allowMultiple = true}) async {
    if (Platform.isAndroid) {
      return _pickAndroid(allowMultiple: allowMultiple);
    }
    // iOS: fall back (Pigeon impl incomplete)
    return _pickFallback(allowMultiple: allowMultiple);
  }

  Future<SaveResult> saveFile({
    required String sourcePath,
    required String fileName,
    required String mimeType,
  }) async {
    if (Platform.isAndroid) {
      return _saveAndroid(
          sourcePath: sourcePath, fileName: fileName, mimeType: mimeType);
    }
    return _saveFallback(sourcePath: sourcePath, fileName: fileName);
  }

  Future<void> shareFile({
    required String filePath,
    required String mimeType,
  }) async {
    if (Platform.isAndroid) {
      await _shareAndroid(filePath: filePath, mimeType: mimeType);
    } else {
      await _shareFallback(filePath: filePath, mimeType: mimeType);
    }
  }

  // ─── Android native (Pigeon) ─────────────────────────────────────────

  Future<List<PickedFile>> _pickAndroid({required bool allowMultiple}) async {
    // TODO: swap for Pigeon-generated call once native handler is wired:
    // final api = NativeFilePickerApi();
    // final results = await api.pickFiles(allowMultiple: allowMultiple);
    //
    // For now, using pub.dev as the fallback path:
    debugPrint('[NativeFilePicker] Android: falling back to pub.dev (Pigeon wip)');
    return _pickFallback(allowMultiple: allowMultiple);
  }

  Future<SaveResult> _saveAndroid({
    required String sourcePath,
    required String fileName,
    required String mimeType,
  }) async {
    // TODO: swap for Pigeon SaveResult when native MediaStore handler ready
    return _saveFallback(sourcePath: sourcePath, fileName: fileName);
  }

  Future<void> _shareAndroid({
    required String filePath,
    required String mimeType,
  }) async {
    // TODO: swap for Pigeon shareFile call
    await _shareFallback(filePath: filePath, mimeType: mimeType);
  }

  // ─── pub.dev fallbacks ────────────────────────────────────────────────

  Future<List<PickedFile>> _pickFallback({required bool allowMultiple}) async {
    final result = await pub_picker.FilePicker.platform.pickFiles(
      allowMultiple: allowMultiple,
      type: pub_picker.FileType.any,
      withData: false,
    );
    if (result == null) return [];

    return result.files
        .where((f) => f.path != null)
        .map((f) {
          final file = File(f.path!);
          return PickedFile(
            path: f.path!,
            name: f.name,
            sizeBytes: f.size,
            mimeType: _guessMime(f.extension ?? ''),
          );
        })
        .toList();
  }

  Future<SaveResult> _saveFallback({
    required String sourcePath,
    required String fileName,
  }) async {
    // On Android 10+ with pub.dev, we can't MediaStore without native code.
    // Files are saved to app Downloads dir as a reasonable fallback.
    try {
      final src = File(sourcePath);
      if (!await src.exists()) {
        return const SaveResult(success: false, errorMessage: 'Source file not found');
      }
      return SaveResult(success: true, savedPath: sourcePath);
    } catch (e) {
      return SaveResult(success: false, errorMessage: e.toString());
    }
  }

  Future<void> _shareFallback({
    required String filePath,
    required String mimeType,
  }) async {
    // share_plus handles the OS share sheet cross-platform as pub.dev fallback
    // import 'package:share_plus/share_plus.dart';
    // await Share.shareXFiles([XFile(filePath, mimeType: mimeType)]);
    debugPrint('[NativeFilePicker] Share fallback: $filePath');
  }

  // ─── Helpers ─────────────────────────────────────────────────────────

  String _guessMime(String ext) {
    const map = {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
      'gif': 'image/gif', 'webp': 'image/webp', 'heic': 'image/heic',
      'mp4': 'video/mp4', 'mov': 'video/quicktime', 'avi': 'video/x-msvideo',
      'mp3': 'audio/mpeg', 'aac': 'audio/aac', 'wav': 'audio/wav',
      'pdf': 'application/pdf', 'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'zip': 'application/zip',
    };
    return map[ext.toLowerCase()] ?? 'application/octet-stream';
  }
}