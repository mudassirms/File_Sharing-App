import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/models/transfer.dart';
import '../../../core/services/identity_service.dart';
import '../../../core/services/transfer_service.dart';
import '../../../core/utils/file_utils.dart';
import '../../../shared/theme/app_theme.dart';

class TransferDetailScreen extends ConsumerStatefulWidget {
  final String transferId;
  const TransferDetailScreen({super.key, required this.transferId});

  @override
  ConsumerState<TransferDetailScreen> createState() =>
      _TransferDetailScreenState();
}

class _TransferDetailScreenState
    extends ConsumerState<TransferDetailScreen> {
  final Map<String, (int, int)> _downloadProgress = {};
  final Map<String, File?> _downloadedFiles = {};
  final Map<String, String?> _downloadErrors = {};
  final Set<String> _downloading = {};

  // ── Permission helper ─────────────────────────────────────────────────────
  //
  // Android permission model by API level:
  //
  //  API ≤ 28  (Android 8.1-)  → WRITE_EXTERNAL_STORAGE required
  //  API 29-32 (Android 10-12) → App-specific external dir needs NO permission.
  //                               MANAGE_EXTERNAL_STORAGE only needed to access
  //                               arbitrary paths (we don't need that).
  //  API 33+   (Android 13+)   → No storage permission needed for app-specific dirs.
  //
  // We always save to getExternalStorageDirectory() (app-specific external dir),
  // so permission is only required on API ≤ 28.
  //
  // The old code requested MANAGE_EXTERNAL_STORAGE unconditionally and had a
  // logic bug where a granted result still fell through to request legacy
  // storage — causing false "denied" results on modern Android.
  //
  // Returns true if the download may proceed.

  Future<bool> _ensureStoragePermission() async {
    if (kIsWeb) return true;
    if (!Platform.isAndroid) return true;

    final sdkInt = await _androidSdkInt();

    // API 29+ — no permission needed for app-specific external storage.
    if (sdkInt >= 29) return true;

    // API 28 and below — need legacy WRITE_EXTERNAL_STORAGE.
    final status = await Permission.storage.status;
    if (status.isGranted) return true;

    final result = await Permission.storage.request();
    if (result.isGranted) return true;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isPermanentlyDenied
                ? 'Storage permission permanently denied. Enable it in Settings.'
                : 'Storage permission denied.',
          ),
          action: result.isPermanentlyDenied
              ? SnackBarAction(
                  label: 'Settings',
                  textColor: AppTheme.goldLight,
                  onPressed: openAppSettings,
                )
              : null,
        ),
      );
    }
    return false;
  }

  Future<int> _androidSdkInt() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.version.sdkInt;
    } catch (_) {
      return 30; // Safe fallback: treat as modern API, skip permission request.
    }
  }

  // ── Save directory ────────────────────────────────────────────────────────
  //
  // getExternalStorageDirectory() returns the app-specific external dir
  // (e.g. /storage/emulated/0/Android/data/<package>/files).
  // No storage permission is required to read/write here on API 29+.
  // Falls back to internal documents dir if external storage is unavailable.

  Future<String> _getSaveDirectory() async {
    if (Platform.isAndroid) {
      try {
        final dir = await getExternalStorageDirectory();
        if (dir != null) {
          await dir.create(recursive: true);
          return dir.path;
        }
      } catch (_) {
        // External storage not mounted — fall through to internal dir.
      }
    }
    final dir = await getApplicationDocumentsDirectory();
    await dir.create(recursive: true);
    return dir.path;
  }

  // ── Download ──────────────────────────────────────────────────────────────

  Future<void> _downloadFile(Transfer transfer, TransferFile tf) async {
    if (_downloading.contains(tf.id)) return;

    final permitted = await _ensureStoragePermission();
    if (!permitted) return;

    HapticFeedback.lightImpact();
    setState(() {
      _downloading.add(tf.id);
      _downloadErrors.remove(tf.id);
    });

    try {
      final dir = kIsWeb ? '' : await _getSaveDirectory();
      final service = ref.read(transferServiceProvider);

      await for (final p in service.downloadFile(
        transfer: transfer,
        tf: tf,
        saveDirectory: dir,
      )) {
        if (!mounted) return;
        setState(() {
          _downloadProgress[tf.id] = (p.received, p.total);
          if (p.file != null) _downloadedFiles[tf.id] = p.file;
        });
      }

      final user = await ref.read(currentUserProvider.future);
      if (transfer.recipientUid == user.uid) {
        final allDone =
            transfer.files.every((f) => _downloadedFiles.containsKey(f.id));
        if (allDone) {
          await ref
              .read(transferServiceProvider)
              .markCompleted(transfer.id);
        }
      }

      if (mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    color: Colors.white70, size: 15),
                const SizedBox(width: 8),
                Text(kIsWeb
                    ? '${tf.name} download started'
                    : '${tf.name} saved'),
              ],
            ),
          ),
        );
      }
    } on HashMismatchException catch (e) {
      if (mounted) setState(() => _downloadErrors[tf.id] = e.toString());
    } catch (e) {
      if (mounted) setState(() => _downloadErrors[tf.id] = e.toString());
    } finally {
      if (mounted) setState(() => _downloading.remove(tf.id));
    }
  }

  Future<void> _downloadAll(Transfer transfer) async {
    for (final file in transfer.files) {
      if (!_downloadedFiles.containsKey(file.id)) {
        await _downloadFile(transfer, file);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.read(transferServiceProvider);
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: StreamBuilder<Transfer?>(
        stream: service.watchTransfer(widget.transferId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const _LoadingBody();
          final transfer = snapshot.data;
          if (transfer == null) return const _NotFoundBody();
          return _DetailBody(
            transfer: transfer,
            downloadProgress: _downloadProgress,
            downloadedFiles: _downloadedFiles,
            downloadErrors: _downloadErrors,
            downloading: _downloading,
            onDownloadFile: (tf) => _downloadFile(transfer, tf),
            onDownloadAll: () => _downloadAll(transfer),
          );
        },
      ),
    );
  }
}

// ── Shells ────────────────────────────────────────────────────────────────────

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
          color: AppTheme.primary, strokeWidth: 2),
    );
  }
}

class _NotFoundBody extends StatelessWidget {
  const _NotFoundBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Transfer not found',
          style: TextStyle(color: AppTheme.textSecondary)),
    );
  }
}

// ── Detail body ───────────────────────────────────────────────────────────────

class _DetailBody extends StatelessWidget {
  final Transfer transfer;
  final Map<String, (int, int)> downloadProgress;
  final Map<String, File?> downloadedFiles;
  final Map<String, String?> downloadErrors;
  final Set<String> downloading;
  final void Function(TransferFile) onDownloadFile;
  final VoidCallback onDownloadAll;

  const _DetailBody({
    required this.transfer,
    required this.downloadProgress,
    required this.downloadedFiles,
    required this.downloadErrors,
    required this.downloading,
    required this.onDownloadFile,
    required this.onDownloadAll,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _DetailAppBar(transfer: transfer)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _AnimatedChild(
                delay: 80,
                child: _MetaCard(transfer: transfer),
              ),
              const SizedBox(height: 14),
              if (transfer.status == TransferStatus.uploading)
                _AnimatedChild(
                  delay: 120,
                  child: _UploadProgressCard(transfer: transfer),
                ),

                // Add this after the uploading card check:
if (transfer.status == TransferStatus.pendingAcceptance)
  _AnimatedChild(
    delay: 120,
    child: _StatusBanner(
      icon: Icons.hourglass_top_rounded,
      fg: AppTheme.warning,
      bg: AppTheme.warningBg,
      borderColor: AppTheme.warning.withOpacity(0.25),
      title: 'Awaiting recipient approval',
      message: 'Waiting for ${transfer.recipientCode} to accept the transfer',
    ),
  ),

              if (transfer.status == TransferStatus.available ||
                  transfer.status == TransferStatus.downloading ||
                  transfer.status == TransferStatus.completed) ...[
                _AnimatedChild(
                  delay: 120,
                  child: _SectionHeader(
                    label: 'Files',
                    trailing: transfer.files
                            .every((f) => downloadedFiles.containsKey(f.id))
                        ? null
                        : _DownloadAllButton(onTap: onDownloadAll),
                  ),
                ),
                const SizedBox(height: 10),
                ...transfer.files.asMap().entries.map((e) {
                  final i = e.key;
                  final tf = e.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AnimatedChild(
                      delay: 180 + i * 50,
                      child: _FileCard(
                        tf: tf,
                        isDownloading: downloading.contains(tf.id),
                        progress: downloadProgress[tf.id],
                        downloadedFile: downloadedFiles[tf.id],
                        error: downloadErrors[tf.id],
                        onDownload: () => onDownloadFile(tf),
                      ),
                    ),
                  );
                }),
              ],
              if (transfer.status == TransferStatus.failed)
                _AnimatedChild(
                  delay: 120,
                  child: _StatusBanner(
                    icon: Icons.error_outline_rounded,
                    fg: AppTheme.error,
                    bg: AppTheme.errorBg,
                    borderColor: AppTheme.errorBorder,
                    title: 'Transfer failed',
                    message:
                        transfer.errorMessage ?? 'An unknown error occurred',
                  ),
                ),
              if (transfer.status == TransferStatus.expired)
                _AnimatedChild(
                  delay: 120,
                  child: _StatusBanner(
                    icon: Icons.timer_off_outlined,
                    fg: AppTheme.warning,
                    bg: AppTheme.warningBg,
                    borderColor: AppTheme.warning.withOpacity(0.25),
                    title: 'Transfer expired',
                    message: 'This transfer exceeded the 48-hour limit',
                  ),
                ),
            ]),
          ),
        ),
      ],
    );
  }
}

// ── Safe animation wrapper ────────────────────────────────────────────────────

class _AnimatedChild extends StatefulWidget {
  final Widget child;
  final int delay;
  const _AnimatedChild({required this.child, required this.delay});

  @override
  State<_AnimatedChild> createState() => _AnimatedChildState();
}

class _AnimatedChildState extends State<_AnimatedChild>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future.delayed(Duration(milliseconds: widget.delay), () {
        if (mounted) _ctrl.forward();
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _opacity,
        child: SlideTransition(position: _slide, child: widget.child),
      );
}

// ── App bar ───────────────────────────────────────────────────────────────────

class _DetailAppBar extends StatelessWidget {
  final Transfer transfer;
  const _DetailAppBar({required this.transfer});

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(8, topPadding + 8, 20, 14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        border: Border(
            bottom: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 17),
            color: AppTheme.textPrimary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TRANSFER DETAILS',
                    style: TextStyle(
                        color: AppTheme.gold,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2)),
                const SizedBox(height: 2),
                SelectableText(
                  transfer.id.substring(0, 8).toUpperCase(),
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          _StatusChip(status: transfer.status),
        ],
      ),
    );
  }
}

// ── Status chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final TransferStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, Color border, String label) = switch (status) {
  TransferStatus.pendingAcceptance => (AppTheme.warning, AppTheme.warningBg, AppTheme.warning.withOpacity(0.25), 'Awaiting'),  // ← add this
  TransferStatus.available   => (AppTheme.accent, AppTheme.accentBg, AppTheme.accentBorder, 'Ready'),
  TransferStatus.completed   => (AppTheme.accent, AppTheme.accentBg, AppTheme.accentBorder, 'Done'),
  TransferStatus.uploading   => (AppTheme.primaryLight, AppTheme.surface, AppTheme.borderMid, 'Uploading'),
  TransferStatus.downloading => (AppTheme.primaryLight, AppTheme.surface, AppTheme.borderMid, 'Downloading'),
  TransferStatus.failed      => (AppTheme.error, AppTheme.errorBg, AppTheme.errorBorder, 'Failed'),
  TransferStatus.expired     => (AppTheme.warning, AppTheme.warningBg, AppTheme.warning.withOpacity(0.25), 'Expired'),
  TransferStatus.cancelled   => (AppTheme.textMuted, AppTheme.surfaceHighlight, AppTheme.border, 'Cancelled'),
  _                          => (AppTheme.textMuted, AppTheme.surfaceHighlight, AppTheme.border, 'Pending'),
};
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border, width: 0.5)),
      child: Text(label,
          style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2)),
    );
  }
}

// ── Meta card ─────────────────────────────────────────────────────────────────

class _MetaCard extends StatelessWidget {
  final Transfer transfer;
  const _MetaCard({required this.transfer});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.border, width: 0.5)),
      child: Column(
        children: [
          Row(
            children: [
              _AddressBlock(label: 'FROM', code: transfer.senderCode),
              Expanded(
                child: Column(children: [
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        AppTheme.border,
                        AppTheme.gold.withOpacity(0.6),
                        AppTheme.border,
                      ]),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(Icons.arrow_forward_rounded,
                      color: AppTheme.gold, size: 13),
                ]),
              ),
              _AddressBlock(
                  label: 'TO', code: transfer.recipientCode, alignRight: true),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              _StatItem(
                  icon: Icons.insert_drive_file_outlined,
                  label: 'Files',
                  value: '${transfer.files.length}'),
              _divider(),
              _StatItem(
                  icon: Icons.storage_outlined,
                  label: 'Size',
                  value: Transfer.formatBytes(transfer.totalBytes)),
              _divider(),
              _StatItem(
                  icon: Icons.timer_outlined,
                  label: 'Expires',
                  value: _formatExpiry(transfer.expiresAt)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
      width: 0.5,
      height: 32,
      color: AppTheme.border,
      margin: const EdgeInsets.symmetric(horizontal: 12));

  String _formatExpiry(DateTime dt) {
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return 'Expired';
    if (diff.inHours > 0) return '${diff.inHours}h ${diff.inMinutes % 60}m';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'Soon';
  }
}

class _AddressBlock extends StatelessWidget {
  final String label;
  final String code;
  final bool alignRight;
  const _AddressBlock(
      {required this.label, required this.code, this.alignRight = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: AppTheme.gold,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5)),
        const SizedBox(height: 5),
        GestureDetector(
          onLongPress: () => Clipboard.setData(ClipboardData(text: code)),
          child: Text(code,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  fontFamily: 'monospace')),
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatItem(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(children: [
        Icon(icon, color: AppTheme.textMuted, size: 15),
        const SizedBox(height: 5),
        Text(label,
            style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3)),
        const SizedBox(height: 3),
        Text(value,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ── Upload progress card ──────────────────────────────────────────────────────

class _UploadProgressCard extends StatelessWidget {
  final Transfer transfer;
  const _UploadProgressCard({required this.transfer});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border, width: 0.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('UPLOADING',
                style: TextStyle(
                    color: AppTheme.gold,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2)),
            const Spacer(),
            Text(
                '${(transfer.overallProgress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          LinearPercentIndicator(
            lineHeight: 4,
            percent: transfer.overallProgress.clamp(0.0, 1.0),
            backgroundColor: AppTheme.surfaceHighlight,
            progressColor: AppTheme.gold,
            barRadius: const Radius.circular(2),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          Text(
              '${Transfer.formatBytes(transfer.transferredBytes)} / ${Transfer.formatBytes(transfer.totalBytes)}',
              style:
                  const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final Widget? trailing;
  const _SectionHeader({required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5)),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ── Download all button ───────────────────────────────────────────────────────

class _DownloadAllButton extends StatelessWidget {
  final VoidCallback onTap;
  const _DownloadAllButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(9)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.download_rounded, color: Colors.white, size: 13),
            SizedBox(width: 6),
            Text('Download all',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── File card ─────────────────────────────────────────────────────────────────

class _FileCard extends StatelessWidget {
  final TransferFile tf;
  final bool isDownloading;
  final (int, int)? progress;
  final File? downloadedFile;
  final String? error;
  final VoidCallback onDownload;

  const _FileCard({
    required this.tf,
    required this.isDownloading,
    required this.progress,
    required this.downloadedFile,
    required this.error,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = !kIsWeb && downloadedFile != null;
    final isWebDone = kIsWeb &&
        progress != null &&
        progress!.$1 > 0 &&
        progress!.$1 == progress!.$2;
    final anyDone = isDone || isWebDone;

    final downloadPct = progress != null && progress!.$2 > 0
        ? progress!.$1 / progress!.$2
        : 0.0;

    final (Color fg, Color bg, String ext) = _chipColors(tf.mimeType);

    Color borderColor = AppTheme.border;
    Color cardBg = AppTheme.surfaceElevated;
    if (error != null) {
      borderColor = AppTheme.errorBorder;
      cardBg = AppTheme.errorBg;
    } else if (anyDone) {
      borderColor = AppTheme.accentBorder;
      cardBg = AppTheme.accentBg.withOpacity(0.4);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 0.5)),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: bg, borderRadius: BorderRadius.circular(11)),
                alignment: Alignment.center,
                child: Text(ext,
                    style: TextStyle(
                        color: fg,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        fontFamily: 'monospace')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onLongPress: () =>
                          Clipboard.setData(ClipboardData(text: tf.name)),
                      child: Text(tf.name,
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 2),
                    Text(FileUtils.formatBytes(tf.sizeBytes),
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _ActionButton(
                isDone: isDone,
                isWebDone: isWebDone,
                isDownloading: isDownloading,
                hasError: error != null,
                downloadedFile: downloadedFile,
                tf: tf,
                onDownload: onDownload,
              ),
            ],
          ),
          if (isDownloading && progress != null && progress!.$2 > 0) ...[
            const SizedBox(height: 12),
            LinearPercentIndicator(
              lineHeight: 3,
              percent: downloadPct.clamp(0.0, 1.0),
              backgroundColor: AppTheme.surfaceHighlight,
              progressColor: AppTheme.primary,
              barRadius: const Radius.circular(2),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${(downloadPct * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
                Text(
                    '${FileUtils.formatBytes(progress!.$1)} / ${FileUtils.formatBytes(progress!.$2)}',
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 10)),
              ],
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AppTheme.errorBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppTheme.errorBorder, width: 0.5)),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppTheme.error, size: 13),
                  const SizedBox(width: 6),
                  Expanded(
                    child: GestureDetector(
                      onLongPress: () =>
                          Clipboard.setData(ClipboardData(text: error!)),
                      child: Text(error!,
                          style: const TextStyle(
                              color: AppTheme.error, fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  (Color fg, Color bg, String ext) _chipColors(String mime) {
    if (mime.contains('pdf'))
      return (AppTheme.chipPdfFg, AppTheme.chipPdfBg, 'PDF');
    if (mime.startsWith('image/'))
      return (AppTheme.chipImgFg, AppTheme.chipImgBg, 'IMG');
    if (mime.startsWith('video/'))
      return (AppTheme.chipPdfFg, AppTheme.chipPdfBg, 'VID');
    if (mime.startsWith('audio/'))
      return (AppTheme.chipDocFg, AppTheme.chipDocBg, 'AUD');
    if (mime.contains('zip') || mime.contains('archive'))
      return (AppTheme.chipZipFg, AppTheme.chipZipBg, 'ZIP');
    if (mime.contains('word') || mime.contains('document'))
      return (AppTheme.chipDocFg, AppTheme.chipDocBg, 'DOC');
    return (AppTheme.chipDefaultFg, AppTheme.chipDefaultBg, 'FILE');
  }
}

// ── Action button ─────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final bool isDone;
  final bool isWebDone;
  final bool isDownloading;
  final bool hasError;
  final File? downloadedFile;
  final TransferFile tf;
  final VoidCallback onDownload;

  const _ActionButton({
    required this.isDone,
    required this.isWebDone,
    required this.isDownloading,
    required this.hasError,
    required this.downloadedFile,
    required this.tf,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    if (isWebDone) {
      return _chip(AppTheme.accentBg, AppTheme.accentBorder,
          AppTheme.accent, Icons.check_rounded, null);
    }
    if (isDone) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _chip(AppTheme.surface, AppTheme.border, AppTheme.textSecondary,
              Icons.open_in_new_rounded,
              () => OpenFilex.open(downloadedFile!.path)),
          const SizedBox(width: 6),
          _chip(AppTheme.surface, AppTheme.border, AppTheme.textSecondary,
              Icons.share_rounded,
              () => Share.shareXFiles([XFile(downloadedFile!.path)])),
        ],
      );
    }
    if (isDownloading) {
      return const SizedBox(
        width: 36,
        height: 36,
        child: CircularProgressIndicator(
            strokeWidth: 2, color: AppTheme.primary),
      );
    }
    return GestureDetector(
      onTap: hasError ? null : onDownload,
      behavior: HitTestBehavior.opaque,
      child: hasError
          ? _chip(AppTheme.errorBg, AppTheme.errorBorder, AppTheme.error,
              Icons.error_outline_rounded, null)
          : _chip(AppTheme.primary, AppTheme.primary, Colors.white,
              Icons.download_rounded, null),
    );
  }

  Widget _chip(Color bg, Color border, Color icon, IconData iconData,
      VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border, width: 0.5)),
        child: Icon(iconData, color: icon, size: 16),
      ),
    );
  }
}

// ── Status banner ─────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final Color fg;
  final Color bg;
  final Color borderColor;
  final String title;
  final String message;

  const _StatusBanner({
    required this.icon,
    required this.fg,
    required this.bg,
    required this.borderColor,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 0.5)),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: fg.withOpacity(0.1),
                borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: fg, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: fg,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(message,
                    style:
                        TextStyle(color: fg.withOpacity(0.7), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}