import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/models/transfer.dart';
import '../../../../core/services/identity_service.dart';
import '../../../../core/services/transfer_service.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/transfer_card.dart';

class ReceiveScreen extends ConsumerWidget {
  const ReceiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return SelectionArea(
      child: Scaffold(
        backgroundColor: AppTheme.surface,
        appBar: AppBar(title: const Text('Incoming')),
        body: userAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(
                color: AppTheme.primary, strokeWidth: 2),
          ),
          error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppTheme.error)),
          ),
          data: (user) {
            final service = ref.read(transferServiceProvider);
            return StreamBuilder<List<Transfer>>(
              stream: service.incomingTransfers(user.uid),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.primary, strokeWidth: 2),
                  );
                }
                final transfers = snapshot.data!;
                if (transfers.isEmpty) {
                  return const Center(
                    child: Text(
                      'No incoming transfers',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  );
                }

                // Split into pending vs rest
                final pending = transfers
                    .where((t) =>
                        t.status == TransferStatus.pendingAcceptance)
                    .toList();
                final others = transfers
                    .where((t) =>
                        t.status != TransferStatus.pendingAcceptance)
                    .toList();

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // ── Pending acceptance section ──────────────────
                    if (pending.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'AWAITING YOUR RESPONSE',
                          style: TextStyle(
                            color: AppTheme.gold,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      ...pending.map((t) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _PendingTransferCard(
                              transfer: t,
                              onAccept: () =>
                                  _handleAccept(context, ref, t),
                              onDecline: () =>
                                  _handleDecline(context, ref, t),
                              onTap: () => context
                                  .go('/home/transfer/${t.id}'),
                            ),
                          )),
                      if (others.isNotEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          child: Divider(color: AppTheme.border),
                        ),
                    ],

                    // ── All other transfers ─────────────────────────
                    if (others.isNotEmpty) ...[
                      if (pending.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'TRANSFERS',
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ...others
                          .asMap()
                          .entries
                          .map((e) => Padding(
                                padding: EdgeInsets.only(
                                    bottom:
                                        e.key < others.length - 1
                                            ? 10
                                            : 0),
                                child: TransferCard(
                                  transfer: e.value,
                                  isIncoming: true,
                                  onTap: () => context.go(
                                      '/home/transfer/${e.value.id}'),
                                ),
                              )),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _handleAccept(
      BuildContext context, WidgetRef ref, Transfer transfer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _AcceptDialog(transfer: transfer),
    );
    if (confirmed != true) return;

    try {
      await ref.read(transferServiceProvider).acceptTransfer(transfer.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _handleDecline(
      BuildContext context, WidgetRef ref, Transfer transfer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeclineDialog(transfer: transfer),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(transferServiceProvider)
          .declineTransfer(transfer.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transfer declined.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to decline: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }
}

// ── Pending transfer card ─────────────────────────────────────────────────────

class _PendingTransferCard extends StatelessWidget {
  final Transfer transfer;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onTap;

  const _PendingTransferCard({
    required this.transfer,
    required this.onAccept,
    required this.onDecline,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.gold.withOpacity(0.45),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.gold.withOpacity(0.07),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppTheme.gold.withOpacity(0.3),
                        width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.mark_email_unread_outlined,
                          color: AppTheme.gold, size: 11),
                      const SizedBox(width: 5),
                      Text(
                        'INCOMING REQUEST',
                        style: TextStyle(
                          color: AppTheme.gold,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  _formatAge(transfer.createdAt),
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // From / file info
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FROM',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        transfer.senderCode,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${transfer.files.length} file${transfer.files.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Transfer.formatBytes(transfer.totalBytes),
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Accept / Decline buttons
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onDecline,
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.errorBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppTheme.errorBorder, width: 0.5),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.close_rounded,
                              color: AppTheme.error, size: 15),
                          SizedBox(width: 6),
                          Text('Decline',
                              style: TextStyle(
                                color: AppTheme.error,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: onAccept,
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.check_rounded,
                              color: Colors.white, size: 15),
                          SizedBox(width: 6),
                          Text('Accept Transfer',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatAge(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ── Accept dialog ─────────────────────────────────────────────────────────────

class _AcceptDialog extends StatelessWidget {
  final Transfer transfer;
  const _AcceptDialog({required this.transfer});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceElevated,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.download_rounded,
                color: AppTheme.primary, size: 19),
          ),
          const SizedBox(width: 12),
          const Text('Accept Transfer?',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${transfer.senderCode} wants to send you:',
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border, width: 0.5),
            ),
            child: Column(
              children: [
                _DialogRow(
                  icon: Icons.insert_drive_file_outlined,
                  label: 'Files',
                  value:
                      '${transfer.files.length} file${transfer.files.length == 1 ? '' : 's'}',
                ),
                const SizedBox(height: 8),
                _DialogRow(
                  icon: Icons.storage_outlined,
                  label: 'Total size',
                  value: Transfer.formatBytes(transfer.totalBytes),
                ),
                if (transfer.files.length <= 4) ...[
                  const SizedBox(height: 10),
                  Divider(color: AppTheme.border, height: 1),
                  const SizedBox(height: 10),
                  ...transfer.files.map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(
                                Icons.insert_drive_file_rounded,
                                color: AppTheme.textMuted,
                                size: 13),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                f.name,
                                style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel',
              style: TextStyle(color: AppTheme.textMuted)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Accept',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

// ── Decline dialog ────────────────────────────────────────────────────────────

class _DeclineDialog extends StatelessWidget {
  final Transfer transfer;
  const _DeclineDialog({required this.transfer});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceElevated,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.errorBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.block_rounded,
                color: AppTheme.error, size: 19),
          ),
          const SizedBox(width: 12),
          const Text('Decline Transfer?',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
        ],
      ),
      content: Text(
        'The transfer from ${transfer.senderCode} will be rejected and the files will be deleted.',
        style:
            const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel',
              style: TextStyle(color: AppTheme.textMuted)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.error,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Decline',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

// ── Small helper ──────────────────────────────────────────────────────────────

class _DialogRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DialogRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.textMuted, size: 13),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                color: AppTheme.textMuted, fontSize: 12)),
        const Spacer(),
        Text(value,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}