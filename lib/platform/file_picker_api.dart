// dart run pigeon --input pigeons/file_picker_api.dart
// Generates:
//   lib/core/platform/file_picker_api.g.dart  (Dart glue)
//   android/app/src/main/kotlin/…/FilePickerApi.kt
//   ios/Runner/FilePickerApi.swift

import 'package:pigeon/pigeon.dart';

export 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/core/platform/file_picker_api.g.dart',
  dartOptions: DartOptions(),
  kotlinOut: 'android/app/src/main/kotlin/com/neosapien/share/FilePickerApi.kt',
  kotlinOptions: KotlinOptions(package: 'com.neosapien.share'),
  swiftOut: 'ios/Runner/FilePickerApi.swift',
  swiftOptions: SwiftOptions(),
))

// ─── Data classes ─────────────────────────────────────────────────────────

class PickedFile {
  /// Absolute path on device (app-scoped temp copy for scoped-storage compat)
  final String path;
  final String name;
  final int sizeBytes;
  final String mimeType;

  PickedFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.mimeType,
  });
}

class SaveRequest {
  final String sourcePath;
  final String fileName;
  final String mimeType;

  SaveRequest({
    required this.sourcePath,
    required this.fileName,
    required this.mimeType,
  });
}

class SaveResult {
  final bool success;
  final String? savedPath;
  final String? errorMessage;

  SaveResult({
    required this.success,
    this.savedPath,
    this.errorMessage,
  });
}

// ─── Host API (native implements, Flutter calls) ───────────────────────────

@HostApi()
abstract class NativeFilePickerApi {
  /// Open the system document picker. Returns null if user cancelled.
  /// Android: ACTION_OPEN_DOCUMENT with CATEGORY_OPENABLE
  /// iOS: UIDocumentPickerViewController
  @async
  List<PickedFile?> pickFiles({required bool allowMultiple});

  /// Write a received file to MediaStore (Android) or Photos/Files (iOS).
  /// Handles scoped-storage and Photos authorization internally.
  @async
  SaveResult saveToGalleryOrDownloads(SaveRequest request);

  /// Invoke the OS share sheet for a local file path.
  @async
  void shareFile({required String filePath, required String mimeType});
}

// ─── Flutter API (Flutter implements, native calls) ────────────────────────

/// Native → Dart callbacks (e.g. background transfer progress updates)
@FlutterApi()
abstract class TransferProgressCallback {
  void onProgress(String transferId, String fileId, double fraction);
  void onComplete(String transferId);
  void onError(String transferId, String message);
}
