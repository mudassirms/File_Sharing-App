// lib/features/send/screens/send_screen.dart
//
// Key changes vs original:
//  - _selectedFiles is now List<AppFile> (not List<File>)
//  - _pickFiles() uses pickAppFiles() helper (web-safe)
//  - size check uses appFile.size (not file.length())
//  - cellular-warning check still works (platform guard inside pickAppFiles)
//  - _startSend() passes List<AppFile> to service.sendFiles()

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:percent_indicator/percent_indicator.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/transfer.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/identity_service.dart';
import '../../../core/services/transfer_service.dart';
import '../../../core/utils/app_file.dart';
import '../../../core/utils/file_picker_helper.dart';
import '../../../core/utils/file_utils.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/file_chip.dart';

enum SendStep { enterCode, pickFiles, uploading, done }

class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key});

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  final _codeController = TextEditingController();
  final _codeFocus = FocusNode();

  SendStep _step = SendStep.enterCode;
  AppUser? _recipient;
  List<AppFile> _selectedFiles = [];   // ← AppFile, not File
  String? _codeError;
  bool _lookingUpCode = false;

  Transfer? _currentTransfer;
  bool _isCancelling = false;

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  // ── Recipient lookup ────────────────────────────────────────────────────

  Future<void> _lookupRecipient() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() {
      _lookingUpCode = true;
      _codeError = null;
    });

    try {
      final me = await ref.read(currentUserProvider.future);
      if (code == me.shortCode) {
        setState(() {
          _codeError = 'You cannot send files to yourself';
          _lookingUpCode = false;
        });
        return;
      }

      final recipient =
          await ref.read(identityServiceProvider).lookupByCode(code);

      if (recipient == null) {
        setState(() {
          _codeError = 'No user found with code "$code"';
          _lookingUpCode = false;
        });
        return;
      }

      setState(() {
        _recipient = recipient;
        _step = SendStep.pickFiles;
        _lookingUpCode = false;
      });
    } catch (e) {
      setState(() {
        _codeError = 'Lookup failed. Check your connection.';
        _lookingUpCode = false;
      });
    }
  }

  // ── File picking ─────────────────────────────────────────────────────────

  Future<void> _pickFiles() async {
    try {
      // pickAppFiles handles web (bytes) vs mobile (path) automatically.
      final picked = await pickAppFiles(allowMultiple: true);
      if (picked == null) return;

      // Size guard
      final oversized = picked
          .where((f) => f.size > maxFileSizeBytes)
          .map((f) => '${f.name} (${FileUtils.formatBytes(f.size)})')
          .toList();

      if (oversized.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Files too large (max 500 MB):\n${oversized.join('\n')}',
                style: const TextStyle(color: AppTheme.error),
              ),
              backgroundColor: AppTheme.surfaceCard,
            ),
          );
        }
        return;
      }

      // Cellular warning (mobile only — skip on web)
      if (!kIsWeb) {
        final isCellular =
            await ref.read(connectivityServiceProvider).isOnCellular;
        if (isCellular && mounted) {
          final proceed = await _showCellularWarning();
          if (!proceed) return;
        }
      }

      setState(() => _selectedFiles = picked);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick files: $e')),
        );
      }
    }
  }

  Future<bool> _showCellularWarning() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.surfaceCard,
            title: const Text('Mobile Data Warning',
                style: TextStyle(color: AppTheme.textPrimary)),
            content: const Text(
              "You're on a metered cellular connection. Sending files may use significant data.",
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Send Anyway'),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ── Send ─────────────────────────────────────────────────────────────────

  Future<void> _startSend() async {
    if (_selectedFiles.isEmpty || _recipient == null) return;

    final me = await ref.read(currentUserProvider.future);
    final service = ref.read(transferServiceProvider);

    setState(() => _step = SendStep.uploading);

    try {
      await for (final transfer in service.sendFiles(
        sender: me,
        recipient: _recipient!,
        files: _selectedFiles,          // ← List<AppFile>
      )) {
        if (!mounted) return;
        setState(() => _currentTransfer = transfer);

       if (transfer.status == TransferStatus.pendingAcceptance ||
    transfer.status == TransferStatus.available ||
    transfer.status == TransferStatus.failed) {
  setState(() => _step = SendStep.done);
  break;
}
      }
    } on FileTooLargeException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
        setState(() => _step = SendStep.pickFiles);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = SendStep.done;
          _currentTransfer = _currentTransfer?.copyWith(
            status: TransferStatus.failed,
            errorMessage: e.toString(),
          );
        });
      }
    }
  }

  Future<void> _cancelUpload() async {
    if (_currentTransfer == null) return;
    setState(() => _isCancelling = true);

    try {
      await ref
          .read(transferServiceProvider)
          .cancelTransfer(_currentTransfer!.id);
    } catch (_) {}

    if (mounted) context.go('/home');
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(_stepTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed:
              _step == SendStep.uploading ? null : () => context.go('/home'),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: switch (_step) {
          SendStep.enterCode => _buildEnterCode(),
          SendStep.pickFiles => _buildPickFiles(),
          SendStep.uploading => _buildUploading(),
          SendStep.done => _buildDone(),
        },
      ),
    );
  }

  String get _stepTitle => switch (_step) {
        SendStep.enterCode => 'Send Files',
        SendStep.pickFiles => 'Select Files',
        SendStep.uploading => 'Uploading...',
       SendStep.done =>
  _currentTransfer?.status == TransferStatus.pendingAcceptance ||
  _currentTransfer?.status == TransferStatus.available
      ? 'Sent!'
      : 'Transfer Failed',
      };

  // ── Step: enter code ─────────────────────────────────────────────────────

  Widget _buildEnterCode() {
    return Padding(
      key: const ValueKey('enter_code'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Enter Recipient's Code",
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Gap(8),
          const Text(
            'Ask them to share their 7-character code from the home screen.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const Gap(32),
          TextField(
            controller: _codeController,
            focusNode: _codeFocus,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            maxLength: 8,
            style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: 6,
            ),
            decoration: InputDecoration(
              hintText: 'AB3CD4E',
              hintStyle: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 28,
                letterSpacing: 6,
              ),
              errorText: _codeError,
              counterText: '',
              suffixIcon: _lookingUpCode
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            onChanged: (v) {
              if (_codeError != null) setState(() => _codeError = null);
            },
            onSubmitted: (_) => _lookupRecipient(),
          ),
          const Gap(24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _lookingUpCode ? null : _lookupRecipient,
              child: const Text('FIND RECIPIENT'),
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  // ── Step: pick files ─────────────────────────────────────────────────────

  Widget _buildPickFiles() {
    final totalSize = _selectedFiles.fold<int>(0, (s, f) => s + f.size);

    return Padding(
      key: const ValueKey('pick_files'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recipient badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_outline,
                    color: AppTheme.primary, size: 18),
                const Gap(8),
                Text(
                  'To: ${_recipient!.shortCode}',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                const Gap(8),
                GestureDetector(
                  onTap: () => setState(() {
                    _step = SendStep.enterCode;
                    _recipient = null;
                  }),
                  child: const Icon(Icons.close,
                      color: AppTheme.textMuted, size: 16),
                ),
              ],
            ),
          ),
          const Gap(24),

          if (_selectedFiles.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_selectedFiles.length} file${_selectedFiles.length == 1 ? '' : 's'} selected',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                ),
                Text(
                  FileUtils.formatBytes(totalSize),
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
            const Gap(12),
            Expanded(
              child: ListView.separated(
                itemCount: _selectedFiles.length,
                separatorBuilder: (_, __) => const Gap(8),
                itemBuilder: (context, index) {
                  final appFile = _selectedFiles[index];
                  // In _buildPickFiles(), replace the FileChip call:
return FileChip(
  file: appFile,
  onRemove: () {
    setState(() {
      _selectedFiles = List.from(_selectedFiles)..removeAt(index);
    });
  },
);
                },
              ),
            ),
            const Gap(12),
          ] else ...[
            Expanded(
              child: GestureDetector(
                onTap: _pickFiles,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_circle_outline,
                          color: AppTheme.primary, size: 48),
                      Gap(16),
                      Text(
                        'Tap to select files',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 16),
                      ),
                      Gap(8),
                      Text(
                        'Images, videos, audio, documents\nUp to 500 MB per file',
                        style: TextStyle(
                            color: AppTheme.textMuted, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Gap(12),
          ],

          Row(
            children: [
              if (_selectedFiles.isNotEmpty)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFiles,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('ADD MORE'),
                  ),
                ),
              if (_selectedFiles.isNotEmpty) const Gap(12),
              Expanded(
                flex: _selectedFiles.isEmpty ? 1 : 2,
                child: ElevatedButton.icon(
                  onPressed:
                      _selectedFiles.isEmpty ? _pickFiles : _startSend,
                  icon: Icon(
                    _selectedFiles.isEmpty
                        ? Icons.folder_open
                        : Icons.upload_rounded,
                    size: 18,
                  ),
                  label: Text(
                      _selectedFiles.isEmpty ? 'SELECT FILES' : 'SEND NOW'),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  // ── Step: uploading ──────────────────────────────────────────────────────

  Widget _buildUploading() {
    final transfer = _currentTransfer;
    if (transfer == null) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }

    return Padding(
      key: const ValueKey('uploading'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Uploading files...',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Gap(8),
          Text(
            'To: ${transfer.recipientCode}',
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const Gap(32),
          LinearPercentIndicator(
            lineHeight: 6,
            percent: transfer.overallProgress.clamp(0.0, 1.0),
            backgroundColor: AppTheme.surfaceCard,
            progressColor: AppTheme.primary,
            barRadius: const Radius.circular(3),
            padding: EdgeInsets.zero,
          ),
          const Gap(8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(transfer.overallProgress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${Transfer.formatBytes(transfer.transferredBytes)} / ${Transfer.formatBytes(transfer.totalBytes)}',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
              ),
            ],
          ),
          const Gap(24),
          const Divider(color: AppTheme.border),
          const Gap(16),
          Expanded(
            child: ListView.separated(
              itemCount: transfer.files.length,
              separatorBuilder: (_, __) => const Gap(12),
              itemBuilder: (context, index) =>
                  _FileProgressRow(file: transfer.files[index]),
            ),
          ),
          const Gap(16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isCancelling ? null : _cancelUpload,
              icon: _isCancelling
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cancel_outlined, size: 18),
              label: Text(_isCancelling ? 'Cancelling...' : 'CANCEL'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.error,
                side: const BorderSide(color: AppTheme.error),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  // ── Step: done ────────────────────────────────────────────────────────────

  Widget _buildDone() {
    final transfer = _currentTransfer;
    final success = transfer?.status == TransferStatus.pendingAcceptance ||
                transfer?.status == TransferStatus.available;


    return Padding(
      key: const ValueKey('done'),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color:
                  (success ? AppTheme.accent : AppTheme.error).withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: success ? AppTheme.accent : AppTheme.error,
                width: 2,
              ),
            ),
            child: Icon(
              success ? Icons.check_rounded : Icons.error_outline,
              color: success ? AppTheme.accent : AppTheme.error,
              size: 40,
            ),
          ).animate().scale(
              begin: const Offset(0.5, 0.5), curve: Curves.easeOutBack),
          const Gap(24),
          Text(
            success ? 'Files Sent!' : 'Transfer Failed',
            style: TextStyle(
              color: success ? AppTheme.accent : AppTheme.error,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ).animate(delay: 200.ms).fadeIn(),
          const Gap(12),
          if (transfer != null)
            Text(
              success
                  ? '${transfer.files.where((f) => f.status == FileStatus.uploaded).length} of ${transfer.files.length} files sent to ${transfer.recipientCode} — waiting for them to accept'
                  : transfer.errorMessage ?? 'An unknown error occurred',
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 15),
              textAlign: TextAlign.center,
            ).animate(delay: 300.ms).fadeIn(),
          const Gap(48),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.go('/home'),
              child: const Text('BACK TO HOME'),
            ),
          ),
          if (!success) ...[
            const Gap(12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => setState(() {
                  _step = SendStep.pickFiles;
                  _currentTransfer = null;
                }),
                child: const Text('TRY AGAIN'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── File progress row (unchanged logic) ─────────────────────────────────

class _FileProgressRow extends StatelessWidget {
  final TransferFile file;

  const _FileProgressRow({required this.file});

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (file.status) {
      FileStatus.uploaded => AppTheme.accent,
      FileStatus.failed => AppTheme.error,
      FileStatus.uploading => AppTheme.primary,
      _ => AppTheme.textMuted,
    };

    final statusIcon = switch (file.status) {
      FileStatus.uploaded => Icons.check_circle_outline,
      FileStatus.failed => Icons.error_outline,
      FileStatus.uploading => Icons.upload_rounded,
      _ => Icons.hourglass_empty,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 16),
              const Gap(8),
              Expanded(
                child: Text(
                  file.name,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Gap(8),
              Text(
                FileUtils.formatBytes(file.sizeBytes),
                style:
                    const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ],
          ),
          if (file.status == FileStatus.uploading) ...[
            const Gap(8),
            LinearPercentIndicator(
              lineHeight: 3,
              percent: file.progress.clamp(0.0, 1.0),
              backgroundColor: AppTheme.surfaceElevated,
              progressColor: AppTheme.primary,
              barRadius: const Radius.circular(2),
              padding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
    );
  }
}