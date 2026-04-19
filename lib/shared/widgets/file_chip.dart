import 'package:flutter/material.dart';
import '../../core/utils/app_file.dart';
import '../../core/utils/file_utils.dart';
import '../theme/app_theme.dart';

class FileChip extends StatelessWidget {
  final AppFile file;
  final VoidCallback onRemove;

  const FileChip({super.key, required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final color = _iconColor(file.mimeType);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(_mimeIcon(file.mimeType), color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  file.name,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  FileUtils.formatBytes(file.size),
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onRemove,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppTheme.error.withOpacity(0.2), width: 0.5),
              ),
              child: const Icon(Icons.close_rounded,
                  color: AppTheme.error, size: 15),
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