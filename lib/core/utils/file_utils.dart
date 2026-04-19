import 'dart:io';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const int maxFileSizeBytes = 500 * 1024 * 1024; // 500 MB

class FileUtils {
  FileUtils._();

  // ── Hashing ──────────────────────────────────────────────────────────────

  /// SHA-256 of a file on disk (mobile / desktop).
  static Future<String> sha256OfFile(File file) async {
    final sink = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(sink);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    return sink.events.single.toString();
  }

  /// SHA-256 of in-memory bytes (web, or when you already have the data).
  static Future<String> sha256OfBytes(Uint8List bytes) async {
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // ── Filename helpers ─────────────────────────────────────────────────────

  /// Strips characters that are unsafe in storage paths.
  static String sanitizeFilename(String name) {
    return p
        .basename(name)
        .replaceAll(RegExp(r'[/\\:*?"<>|]'), '_')
        .substring(0, name.length.clamp(0, 200));
  }

  /// Returns a MIME type string derived from the file extension.
  static String mimeType(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
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

  // ── Size helpers ──────────────────────────────────────────────────────────

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }

  // ── Conflict resolution ───────────────────────────────────────────────────

  /// Returns a [File] that does not yet exist, appending (1), (2) … as needed.
  static Future<File> resolveConflict(String directory, String name) async {
    var candidate = File(p.join(directory, name));
    if (!await candidate.exists()) return candidate;

    final base = p.basenameWithoutExtension(name);
    final ext = p.extension(name);
    var counter = 1;
    while (await candidate.exists()) {
      candidate = File(p.join(directory, '$base ($counter)$ext'));
      counter++;
    }
    return candidate;
  }
}