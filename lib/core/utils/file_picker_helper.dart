import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'app_file.dart';

/// Picks files on any platform and returns [AppFile] instances.
///
/// On web, bytes are eagerly loaded from the picker result.
/// On mobile/desktop, only the path is stored (bytes read on demand).
Future<List<AppFile>?> pickAppFiles({bool allowMultiple = true}) async {
  final result = await FilePicker.platform.pickFiles(
    allowMultiple: allowMultiple,
    type: FileType.any,
    withData: kIsWeb,
    withReadStream: false,
  );

  if (result == null || result.files.isEmpty) return null;

  final List<AppFile> appFiles = [];

  for (final pf in result.files) {
    if (kIsWeb) {
      if (pf.bytes == null) continue;
      appFiles.add(AppFile(
        name: pf.name,
        size: pf.bytes!.length,
        mimeType: _mimeFromName(pf.name),
        bytes: pf.bytes,
        path: null,
      ));
    } else {
      if (pf.path == null) continue;
      final file = File(pf.path!);
      final size = await file.length();
      appFiles.add(AppFile(
        name: pf.name,
        size: size,
        mimeType: _mimeFromName(pf.name),
        path: pf.path,
        bytes: null,
      ));
    }
  }

  return appFiles.isEmpty ? null : appFiles;
}

String _mimeFromName(String name) {
  final ext = name.split('.').last.toLowerCase();
  const map = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'avi': 'video/x-msvideo',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'aac': 'audio/aac',
    'pdf': 'application/pdf',
    'zip': 'application/zip',
    'tar': 'application/x-tar',
    'gz': 'application/gzip',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx':
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'txt': 'text/plain',
    'csv': 'text/csv',
    'json': 'application/json',
  };
  return map[ext] ?? 'application/octet-stream';
}