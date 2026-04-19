// lib/core/models/transfer.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum TransferStatus {
  
  pendingAcceptance,    // queued, recipient offline
  uploading,  // sender uploading chunks
  available,  // all files uploaded, recipient can download
  downloading,// recipient is downloading
  completed,  // recipient confirmed all files received
  failed,     // unrecoverable error
  expired,    // TTL exceeded (48h for offline recipients)
  cancelled,  // sender or system cancelled
}

enum FileStatus {
  pending,
  uploading,
  uploaded,
  downloading,
  saved,
  failed,
}

class TransferFile {
  final String id;
  final String name;
  final int sizeBytes;
  final String mimeType;
  final String? storageRef;      // Firebase Storage path
  final String? downloadUrl;
  final String? sha256Hash;
  final FileStatus status;
  final int bytesTransferred;

  const TransferFile({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.mimeType,
    this.storageRef,
    this.downloadUrl,
    this.sha256Hash,
    this.status = FileStatus.pending,
    this.bytesTransferred = 0,
  });

  factory TransferFile.fromMap(Map<String, dynamic> map) => TransferFile(
        id: map['id'] as String,
        name: map['name'] as String,
        sizeBytes: map['sizeBytes'] as int,
        mimeType: map['mimeType'] as String,
        storageRef: map['storageRef'] as String?,
        downloadUrl: map['downloadUrl'] as String?,
        sha256Hash: map['sha256Hash'] as String?,
        status: FileStatus.values.byName(map['status'] as String? ?? 'pending'),
        bytesTransferred: map['bytesTransferred'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'sizeBytes': sizeBytes,
        'mimeType': mimeType,
        'storageRef': storageRef,
        'downloadUrl': downloadUrl,
        'sha256Hash': sha256Hash,
        'status': status.name,
        'bytesTransferred': bytesTransferred,
      };

  TransferFile copyWith({
    String? storageRef,
    String? downloadUrl,
    String? sha256Hash,
    FileStatus? status,
    int? bytesTransferred,
  }) =>
      TransferFile(
        id: id,
        name: name,
        sizeBytes: sizeBytes,
        mimeType: mimeType,
        storageRef: storageRef ?? this.storageRef,
        downloadUrl: downloadUrl ?? this.downloadUrl,
        sha256Hash: sha256Hash ?? this.sha256Hash,
        status: status ?? this.status,
        bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      );

  double get progress =>
      sizeBytes > 0 ? bytesTransferred / sizeBytes : 0.0;
}

class Transfer {
  final String id;
  final String senderUid;
  final String senderCode;
  final String recipientUid;
  final String recipientCode;
  final List<TransferFile> files;
  final TransferStatus status;
  final DateTime createdAt;
  final DateTime expiresAt;  // createdAt + 48h
  final int totalBytes;
  final int transferredBytes;
  final String? errorMessage;
  final bool senderOnline;

  const Transfer({
    required this.id,
    required this.senderUid,
    required this.senderCode,
    required this.recipientUid,
    required this.recipientCode,
    required this.files,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.totalBytes,
    this.transferredBytes = 0,
    this.errorMessage,
    this.senderOnline = true,
  });

  factory Transfer.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final filesList = (data['files'] as List<dynamic>? ?? [])
        .map((f) => TransferFile.fromMap(f as Map<String, dynamic>))
        .toList();
    return Transfer(
      id: doc.id,
      senderUid: data['senderUid'] as String,
      senderCode: data['senderCode'] as String,
      recipientUid: data['recipientUid'] as String,
      recipientCode: data['recipientCode'] as String,
      files: filesList,
      status: TransferStatus.values.byName(data['status'] as String),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      expiresAt: (data['expiresAt'] as Timestamp).toDate(),
      totalBytes: data['totalBytes'] as int,
      transferredBytes: data['transferredBytes'] as int? ?? 0,
      errorMessage: data['errorMessage'] as String?,
      senderOnline: data['senderOnline'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'senderUid': senderUid,
        'senderCode': senderCode,
        'recipientUid': recipientUid,
        'recipientCode': recipientCode,
        'files': files.map((f) => f.toMap()).toList(),
        'status': status.name,
        'createdAt': Timestamp.fromDate(createdAt),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'totalBytes': totalBytes,
        'transferredBytes': transferredBytes,
        'errorMessage': errorMessage,
        'senderOnline': senderOnline,
      };

  Transfer copyWith({
    List<TransferFile>? files,
    TransferStatus? status,
    int? transferredBytes,
    String? errorMessage,
  }) =>
      Transfer(
        id: id,
        senderUid: senderUid,
        senderCode: senderCode,
        recipientUid: recipientUid,
        recipientCode: recipientCode,
        files: files ?? this.files,
        status: status ?? this.status,
        createdAt: createdAt,
        expiresAt: expiresAt,
        totalBytes: totalBytes,
        transferredBytes: transferredBytes ?? this.transferredBytes,
        errorMessage: errorMessage ?? this.errorMessage,
        senderOnline: senderOnline,
      );

  double get overallProgress =>
      totalBytes > 0 ? transferredBytes / totalBytes : 0.0;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  String get formattedSize => _formatBytes(totalBytes);

  static String formatBytes(int bytes) => _formatBytes(bytes);

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}