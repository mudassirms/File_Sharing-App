import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/app_user.dart';
import '../models/transfer.dart';
import '../utils/file_utils.dart';
import '../utils/app_file.dart';
import '../utils/web_save_stub.dart'
    if (dart.library.html) '../utils/web_save_web.dart';
import 'connectivity_service.dart';

const _transferTtlHours = 48;
const _supabaseBucket = 'transfers';

class TransferService {
  final FirebaseFirestore _db;
  final SupabaseClient _supabase;
  final ConnectivityService _connectivity;

  static const _uuid = Uuid();

  TransferService({
    required FirebaseFirestore db,
    required SupabaseClient supabase,
    required ConnectivityService connectivity,
  })  : _db = db,
        _supabase = supabase,
        _connectivity = connectivity;

  // ─── Connectivity Guard ──────────────────────────────────────────────────

  Future<T> _withConnectivity<T>(Future<T> Function() fn) async {
    final online = await _connectivity.isOnline;
    if (!online) throw const NetworkUnavailableException();

    try {
      return await fn();
    } on SocketException {
      throw const NetworkUnavailableException();
    } on HandshakeException {
      throw const NetworkUnavailableException();
    } on StorageException catch (e) {
      if (_isNetworkError(e.message)) {
        throw const NetworkUnavailableException();
      }
      rethrow;
    } on FirebaseException catch (e) {
      if (_isNetworkError(e.message ?? '')) {
        throw const NetworkUnavailableException();
      }
      rethrow;
    } catch (e) {
      if (_isNetworkError(e.toString())) {
        throw const NetworkUnavailableException();
      }
      rethrow;
    }
  }

  bool _isNetworkError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('socket') ||
        lower.contains('connection') ||
        lower.contains('network') ||
        lower.contains('unreachable') ||
        lower.contains('interrupted') ||
        lower.contains('timeout') ||
        lower.contains('host lookup') ||
        lower.contains('no address') ||
        lower.contains('refused');
  }

  // ─── SEND ───────────────────────────────────────────────────────────────

  Stream<Transfer> sendFiles({
    required AppUser sender,
    required AppUser recipient,
    required List<AppFile> files,
  }) async* {
    // Pre-flight checks
    final online = await _connectivity.isOnline;
    if (!online) throw const NetworkUnavailableException();

    for (final f in files) {
      if (f.size > maxFileSizeBytes) {
        throw FileTooLargeException(f.name, f.size, maxFileSizeBytes);
      }
    }

    if (files.any((f) => f.size == 0)) {
      throw const EmptyFileException();
    }

    final transferId = _uuid.v4();
    final now = DateTime.now();

    final transferFiles = files
        .map((f) => TransferFile(
              id: _uuid.v4(),
              name: FileUtils.sanitizeFilename(f.name),
              sizeBytes: f.size,
              mimeType: f.mimeType,
              status: FileStatus.pending,
            ))
        .toList();

    final totalBytes =
        transferFiles.fold<int>(0, (s, f) => s + f.sizeBytes);

    var transfer = Transfer(
      id: transferId,
      senderUid: sender.uid,
      senderCode: sender.shortCode,
      recipientUid: recipient.uid,
      recipientCode: recipient.shortCode,
      files: transferFiles,
      status: TransferStatus.uploading,
      createdAt: now,
      expiresAt: now.add(const Duration(hours: _transferTtlHours)),
      totalBytes: totalBytes,
    );

    // Create Firestore record
    await _withConnectivity(() => _db
        .collection('transfers')
        .doc(transferId)
        .set(transfer.toFirestore()));
    yield transfer;

    int totalTransferred = 0;
    final updatedFiles = List<TransferFile>.from(transferFiles);

    for (var i = 0; i < files.length; i++) {
      final appFile = files[i];
      var tf = updatedFiles[i];

      // ── Hash ─────────────────────────────────────────────────────────
      final String hash;
      try {
        if (kIsWeb) {
          hash = await FileUtils.sha256OfBytes(appFile.bytes!);
        } else {
          hash = await FileUtils.sha256OfFile(File(appFile.path!));
        }
      } catch (e) {
        updatedFiles[i] = tf.copyWith(status: FileStatus.failed);
        transfer = transfer.copyWith(files: List.from(updatedFiles));
        yield transfer;
        continue;
      }

      final storagePath = '$transferId/${tf.id}/${tf.name}';

      tf = tf.copyWith(status: FileStatus.uploading, sha256Hash: hash);
      updatedFiles[i] = tf;
      transfer = transfer.copyWith(files: List.from(updatedFiles));
      yield transfer;

      try {
        // ── Read bytes ───────────────────────────────────────────────
        final Uint8List bytes;
        if (kIsWeb) {
          bytes = appFile.bytes!;
        } else {
          bytes = await File(appFile.path!).readAsBytes();
        }

        // ── Upload to Supabase ───────────────────────────────────────
        await _withConnectivity(() => _supabase.storage
            .from(_supabaseBucket)
            .uploadBinary(
              storagePath,
              bytes,
              fileOptions: FileOptions(
                contentType: tf.mimeType,
                upsert: true,
              ),
            ));

        final downloadUrl = _supabase.storage
            .from(_supabaseBucket)
            .getPublicUrl(storagePath);

        totalTransferred += tf.sizeBytes;

        tf = tf.copyWith(
          status: FileStatus.uploaded,
          storageRef: storagePath,
          downloadUrl: downloadUrl,
          bytesTransferred: tf.sizeBytes,
        );
        updatedFiles[i] = tf;

        transfer = transfer.copyWith(
          files: List.from(updatedFiles),
          transferredBytes: totalTransferred,
        );

        await _withConnectivity(() => _db
            .collection('transfers')
            .doc(transferId)
            .update({
          'files': updatedFiles.map((f) => f.toMap()).toList(),
          'transferredBytes': totalTransferred,
        }));
        yield transfer;
      } on NetworkUnavailableException {
        // Mark this file failed but continue batch
        updatedFiles[i] = tf.copyWith(status: FileStatus.failed);
        transfer = transfer.copyWith(
          files: List.from(updatedFiles),
          errorMessage:
              'Upload interrupted — check your connection',
        );
        // Try to persist failure without connectivity guard
        // (Firestore has offline persistence so this may succeed)
        try {
          await _db
              .collection('transfers')
              .doc(transferId)
              .update({
            'files': updatedFiles.map((f) => f.toMap()).toList(),
          });
        } catch (_) {}
        yield transfer;
        rethrow; // Bubble up so UI can show network error
      } catch (e) {
        updatedFiles[i] = tf.copyWith(status: FileStatus.failed);
        transfer = transfer.copyWith(files: List.from(updatedFiles));
        try {
          await _db
              .collection('transfers')
              .doc(transferId)
              .update({
            'files': updatedFiles.map((f) => f.toMap()).toList(),
          });
        } catch (_) {}
        yield transfer;
      }
    }

    final allUploaded =
        updatedFiles.every((f) => f.status == FileStatus.uploaded);
    final anyUploaded =
        updatedFiles.any((f) => f.status == FileStatus.uploaded);

    final finalStatus = allUploaded || anyUploaded
        ? TransferStatus.pendingAcceptance // recipient can accept and download, but sender still has files uploading
        : TransferStatus.failed;

    transfer = transfer.copyWith(status: finalStatus);

    try {
      await _withConnectivity(() => _db
          .collection('transfers')
          .doc(transferId)
          .update({
        'status': finalStatus.name,
        'transferredBytes': totalTransferred,
      }));
    } catch (_) {
      // Firestore offline persistence will sync when back online
    }
    yield transfer;
  }
  
  Future<void> acceptTransfer(String transferId) async {
  await _withConnectivity(() => _db
      .collection('transfers')
      .doc(transferId)
      .update({'status': TransferStatus.available.name}));
}

Future<void> declineTransfer(String transferId) async {
  // Optionally clean up storage too (reuse cancelTransfer logic)
  await _withConnectivity(() => _db
      .collection('transfers')
      .doc(transferId)
      .update({'status': TransferStatus.cancelled.name}));
}
  // ─── STREAMS ────────────────────────────────────────────────────────────

  Stream<List<Transfer>> incomingTransfers(String recipientUid) {
    return _db
        .collection('transfers')
        .where('recipientUid', isEqualTo: recipientUid)
        .where('status', whereIn: [
          
          TransferStatus.pendingAcceptance.name,
          TransferStatus.available.name,
          TransferStatus.uploading.name,
          TransferStatus.downloading.name,
          TransferStatus.completed.name,
        ])
        .orderBy('createdAt', descending: true)
        .snapshots()
        .handleError((e) {
          if (e is FirebaseException &&
              _isNetworkError(e.message ?? '')) {
            return <Transfer>[];
          }
          throw e;
        })
        .map((snap) => snap.docs.map(Transfer.fromFirestore).toList());
  }

  Stream<List<Transfer>> outgoingTransfers(String senderUid) {
    return _db
        .collection('transfers')
        .where('senderUid', isEqualTo: senderUid)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .handleError((e) {
          if (e is FirebaseException &&
              _isNetworkError(e.message ?? '')) {
            return <Transfer>[];
          }
          throw e;
        })
        .map((snap) => snap.docs.map(Transfer.fromFirestore).toList());
  }

  Stream<Transfer?> watchTransfer(String transferId) {
    return _db
        .collection('transfers')
        .doc(transferId)
        .snapshots()
        .handleError((e) {
          if (e is FirebaseException &&
              _isNetworkError(e.message ?? '')) {
            return null;
          }
          throw e;
        })
        .map((snap) =>
            snap.exists ? Transfer.fromFirestore(snap) : null);
  }

  // ─── DOWNLOAD ───────────────────────────────────────────────────────────

  Stream<({int received, int total, File? file})> downloadFile({
    required Transfer transfer,
    required TransferFile tf,
    required String saveDirectory,
  }) async* {
    if (tf.storageRef == null) {
      throw Exception('No storage reference found for ${tf.name}');
    }

    final online = await _connectivity.isOnline;
    if (!online) throw const NetworkUnavailableException();

    yield (received: 0, total: tf.sizeBytes, file: null);

    final Uint8List bytes;
    try {
      bytes = await _withConnectivity(() => _supabase.storage
          .from(_supabaseBucket)
          .download(tf.storageRef!));
    } on NetworkUnavailableException {
      rethrow;
    } catch (e) {
      throw Exception(
          'Download failed for ${tf.name}. Please try again.');
    }

    // ── Integrity check ──────────────────────────────────────────────
    if (tf.sha256Hash != null) {
      final computed = await FileUtils.sha256OfBytes(bytes);
      if (computed != tf.sha256Hash) {
        throw HashMismatchException(tf.name);
      }
    }

    if (kIsWeb) {
      webSaveBytes(bytes, tf.name, tf.mimeType);
      yield (received: tf.sizeBytes, total: tf.sizeBytes, file: null);
    } else {
      final dest =
          await FileUtils.resolveConflict(saveDirectory, tf.name);
      await dest.parent.create(recursive: true);
      await dest.writeAsBytes(bytes);
      yield (received: tf.sizeBytes, total: tf.sizeBytes, file: dest);
    }
  }

  // ─── CRUD ────────────────────────────────────────────────────────────────

  Future<void> markCompleted(String transferId) async {
    try {
      await _withConnectivity(() => _db
          .collection('transfers')
          .doc(transferId)
          .update({'status': TransferStatus.completed.name}));
    } catch (_) {
      // Firestore offline persistence will sync this
    }
  }

  Future<void> cancelTransfer(String transferId) async {
    final doc = await _withConnectivity(
        () => _db.collection('transfers').doc(transferId).get());
    if (!doc.exists) return;

    final transfer = Transfer.fromFirestore(doc);

    final paths = transfer.files
        .where((f) => f.storageRef != null)
        .map((f) => f.storageRef!)
        .toList();

    if (paths.isNotEmpty) {
      try {
        await _withConnectivity(() =>
            _supabase.storage.from(_supabaseBucket).remove(paths));
      } catch (_) {
        // Best effort — storage cleanup can fail silently
      }
    }

    await _withConnectivity(() => _db
        .collection('transfers')
        .doc(transferId)
        .update({'status': TransferStatus.cancelled.name}));
  }

  Future<Transfer?> getTransfer(String transferId) async {
    try {
      final doc = await _withConnectivity(
          () => _db.collection('transfers').doc(transferId).get());
      return doc.exists ? Transfer.fromFirestore(doc) : null;
    } on NetworkUnavailableException {
      return null;
    }
  }
}

// ─── Exceptions ──────────────────────────────────────────────────────────

class NetworkUnavailableException implements Exception {
  const NetworkUnavailableException();

  @override
  String toString() =>
      'No internet connection. Please check your network and try again.';
}

class FileTooLargeException implements Exception {
  final String path;
  final int size;
  final int max;

  const FileTooLargeException(this.path, this.size, this.max);

  @override
  String toString() =>
      'File too large: ${FileUtils.formatBytes(size)} (max ${FileUtils.formatBytes(max)})';
}

class EmptyFileException implements Exception {
  const EmptyFileException();

  @override
  String toString() => 'One or more files are empty (0 bytes).';
}

class HashMismatchException implements Exception {
  final String filename;

  const HashMismatchException(this.filename);

  @override
  String toString() =>
      'Integrity check failed for $filename — file may be corrupted';
}

// ─── Provider ─────────────────────────────────────────────────────────────

final transferServiceProvider = Provider<TransferService>((ref) {
  return TransferService(
    db: FirebaseFirestore.instance,
    supabase: Supabase.instance.client,
    connectivity: ref.watch(connectivityServiceProvider),
  );
});