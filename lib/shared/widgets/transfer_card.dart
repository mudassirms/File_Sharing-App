import 'package:flutter/material.dart';
import '../../core/models/transfer.dart';
import '../../core/utils/file_utils.dart';
import '../theme/app_theme.dart';

class TransferCard extends StatelessWidget {
  final Transfer transfer;
  final bool isIncoming;
  final VoidCallback onTap;

  const TransferCard({
    super.key,
    required this.transfer,
    required this.isIncoming,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(transfer.status);
    final isActive = transfer.status == TransferStatus.uploading ||
        transfer.status == TransferStatus.downloading;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? statusColor.withOpacity(0.5)
                : AppTheme.border,
            width: isActive ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                _FileIconStack(files: transfer.files),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            isIncoming
                                ? transfer.senderCode
                                : transfer.recipientCode,
                            style: TextStyle(
                              color: AppTheme.primaryLight,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceHighlight,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isIncoming
                                      ? Icons.arrow_downward_rounded
                                      : Icons.arrow_upward_rounded,
                                  color: AppTheme.textMuted,
                                  size: 10,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  isIncoming ? 'from' : 'to',
                                  style: const TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _fileSummary(transfer),
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // ← pass isIncoming here
                    _StatusPill(
                      status: transfer.status,
                      isIncoming: isIncoming,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      Transfer.formatBytes(transfer.totalBytes),
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (isActive) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: transfer.overallProgress.clamp(0.0, 1.0),
                  backgroundColor: AppTheme.surfaceHighlight,
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  minHeight: 3,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(transfer.overallProgress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${Transfer.formatBytes(transfer.transferredBytes)} / ${Transfer.formatBytes(transfer.totalBytes)}',
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _statusColor(TransferStatus status) => switch (status) {
        TransferStatus.pendingAcceptance => AppTheme.warning,
        TransferStatus.available        => AppTheme.accent,
        TransferStatus.completed        => AppTheme.textMuted,
        TransferStatus.uploading        => AppTheme.primary,
        TransferStatus.downloading      => AppTheme.primary,
        TransferStatus.failed           => AppTheme.error,
        TransferStatus.expired          => AppTheme.warning,
        _                               => AppTheme.textSecondary,
      };

  String _fileSummary(Transfer t) {
    if (t.files.isEmpty) return 'No files';
    if (t.files.length == 1) return t.files.first.name;
    return '${t.files.first.name}  +${t.files.length - 1} more';
  }
}

// ── File icon stack ───────────────────────────────────────────────────────────

class _FileIconStack extends StatelessWidget {
  final List<TransferFile> files;
  const _FileIconStack({required this.files});

  @override
  Widget build(BuildContext context) {
    final mime  = files.isNotEmpty ? files.first.mimeType : '';
    final color = _iconColor(mime);

    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withOpacity(0.25), width: 0.5),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(_mimeIcon(mime), color: color, size: 20),
          if (files.length > 1)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${files.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _iconColor(String mime) {
    if (mime.startsWith('image/')) return const Color(0xFF8B5CF6);
    if (mime.startsWith('video/')) return const Color(0xFFEF4444);
    if (mime.startsWith('audio/')) return const Color(0xFF10B981);
    if (mime.contains('pdf'))      return const Color(0xFFF97316);
    if (mime.contains('zip'))      return const Color(0xFFF59E0B);
    return AppTheme.primaryLight;
  }

  IconData _mimeIcon(String mime) {
    if (mime.startsWith('image/')) return Icons.image_rounded;
    if (mime.startsWith('video/')) return Icons.videocam_rounded;
    if (mime.startsWith('audio/')) return Icons.audiotrack_rounded;
    if (mime.contains('pdf'))      return Icons.picture_as_pdf_rounded;
    if (mime.contains('zip'))      return Icons.folder_zip_rounded;
    return Icons.insert_drive_file_rounded;
  }
}

// ── Status pill ───────────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final TransferStatus status;
  final bool isIncoming;

  const _StatusPill({
    required this.status,
    required this.isIncoming,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      TransferStatus.pendingAcceptance => AppTheme.warning,
      TransferStatus.available        => AppTheme.accent,
      TransferStatus.completed        => AppTheme.textSecondary,
      TransferStatus.uploading        => AppTheme.primary,
      TransferStatus.downloading      => AppTheme.primary,
      TransferStatus.failed           => AppTheme.error,
      TransferStatus.expired          => AppTheme.warning,
      _                               => AppTheme.textSecondary,
    };

    final label = switch (status) {
      TransferStatus.pendingAcceptance => isIncoming ? 'Pending'    : 'Awaiting',
      TransferStatus.available        => isIncoming ? 'Ready'      : 'Sent',
      TransferStatus.completed        => isIncoming ? 'Done'       : 'Delivered',
      TransferStatus.uploading        => isIncoming ? 'Incoming'   : 'Sending',
      TransferStatus.downloading      => isIncoming ? 'Receiving'  : 'Downloading',
      TransferStatus.failed           => 'Failed',
      TransferStatus.expired          => 'Expired',
      TransferStatus.cancelled        => 'Cancelled',
      _                               => 'Pending',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}