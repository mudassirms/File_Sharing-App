import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/models/transfer.dart';
import '../../../../providers.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/transfer_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _selectedTab = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);

    return SelectionArea(
      child: Scaffold(
        backgroundColor: AppTheme.surface,
        body: userAsync.when(
          loading: () => const _LoadingView(),
          error: (e, _) => _ErrorView(error: e.toString()),
          data: (user) => _HomeBody(
            user: user,
            tabController: _tabController,
            selectedTab: _selectedTab,
          ),
        ),
        floatingActionButton: const _SendFAB(),
        floatingActionButtonLocation:
            FloatingActionButtonLocation.centerFloat,
      ),
    );
  }
}

// ── Loading ───────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              color: AppTheme.primary,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Initializing…',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error ─────────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.errorBg,
                shape: BoxShape.circle,
                border:
                    Border.all(color: AppTheme.errorBorder, width: 0.5),
              ),
              child: const Icon(Icons.error_outline_rounded,
                  color: AppTheme.error, size: 24),
            ),
            const SizedBox(height: 16),
            Text(
              error,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _HomeBody extends StatelessWidget {
  final dynamic user;
  final TabController tabController;
  final int selectedTab;

  const _HomeBody({
    required this.user,
    required this.tabController,
    required this.selectedTab,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TopSection(user: user),
        _TabBar(controller: tabController, selectedTab: selectedTab),
        Expanded(
          child: TabBarView(
            controller: tabController,
            children: [
              _TransferList(uid: user.uid, incoming: true),
              _TransferList(uid: user.uid, incoming: false),
            ],
          ),
        ),
        const SizedBox(height: 90),
      ],
    );
  }
}

// ── Top section ───────────────────────────────────────────────────────────────

class _TopSection extends StatelessWidget {
  final dynamic user;
  const _TopSection({required this.user});

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(20, topPadding + 16, 20, 20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NEOSAPIEN',
                    style: TextStyle(
                      color: AppTheme.gold,
                      fontSize: 10,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Share',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      letterSpacing: -0.6,
                    ),
                  ),
                ],
              ),
              const _OnlineBadge(),
            ],
          ),
          const SizedBox(height: 20),
          _CodeCard(code: user.shortCode),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms);
  }
}

// ── Online badge ──────────────────────────────────────────────────────────────

class _OnlineBadge extends StatefulWidget {
  const _OnlineBadge();

  @override
  State<_OnlineBadge> createState() => _OnlineBadgeState();
}

class _OnlineBadgeState extends State<_OnlineBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.accentBg,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: AppTheme.accentBorder, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: AppTheme.accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accent
                        .withOpacity(0.4 + _ctrl.value * 0.3),
                    blurRadius: 4 + _ctrl.value * 4,
                    spreadRadius: _ctrl.value * 1.5,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Text(
              'Online',
              style: TextStyle(
                color: AppTheme.accent,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Code card ─────────────────────────────────────────────────────────────────

class _CodeCard extends StatelessWidget {
  final String code;
  const _CodeCard({required this.code});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: code));
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.check_circle_outline,
                    color: Colors.white70, size: 15),
                SizedBox(width: 8),
                Text('Code copied to clipboard'),
              ],
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.goldPale,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.goldBorder, width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR DEVICE CODE',
                    style: TextStyle(
                      color: AppTheme.gold,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    _formatCode(code),
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 8,
                      fontFamily: 'monospace',
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Share with sender to receive files',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppTheme.gold,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.copy_rounded,
                  color: Colors.white, size: 19),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.06, end: 0);
  }

  String _formatCode(String code) {
    if (code.length <= 4) return code;
    final mid = code.length ~/ 2;
    return '${code.substring(0, mid)}-${code.substring(mid)}';
  }
}

// ── Tab bar ───────────────────────────────────────────────────────────────────

class _TabBar extends StatelessWidget {
  final TabController controller;
  final int selectedTab;

  const _TabBar({required this.controller, required this.selectedTab});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      height: 46,
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(11),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: AppTheme.textSecondary,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        tabs: const [
          Tab(text: 'Inbox'),
          Tab(text: 'Sent'),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms);
  }
}

// ── Transfer list ─────────────────────────────────────────────────────────────

class _TransferList extends ConsumerWidget {
  final String uid;
  final bool incoming;

  const _TransferList({required this.uid, required this.incoming});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfersAsync = incoming
        ? ref.watch(incomingTransfersProvider)
        : ref.watch(outgoingTransfersProvider);

    return transfersAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(
            color: AppTheme.primary, strokeWidth: 2),
      ),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppTheme.errorBg,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppTheme.errorBorder, width: 0.5),
                ),
                child: const Icon(Icons.error_outline_rounded,
                    color: AppTheme.error, size: 22),
              ),
              const SizedBox(height: 16),
              const Text(
                'Failed to load transfers',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                error.toString(),
                style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 12),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => incoming
                    ? ref.refresh(incomingTransfersProvider)
                    : ref.refresh(outgoingTransfersProvider),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (transfers) {
        if (transfers.isEmpty) {
          return _EmptyState(incoming: incoming);
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          itemCount: transfers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final transfer = transfers[index];

            // ── Pending acceptance — show accept/decline card ──────
            if (incoming &&
                transfer.status == TransferStatus.pendingAcceptance) {
              return _PendingCard(transfer: transfer)
                  .animate(delay: (index * 50).ms)
                  .fadeIn()
                  .slideY(
                      begin: 0.06,
                      end: 0,
                      curve: Curves.easeOut);
            }

            // ── All other statuses — normal card ──────────────────
            return TransferCard(
              transfer: transfer,
              isIncoming: incoming,
              onTap: () =>
                  context.go('/home/transfer/${transfer.id}'),
            )
                .animate(delay: (index * 50).ms)
                .fadeIn()
                .slideY(
                    begin: 0.06,
                    end: 0,
                    curve: Curves.easeOut);
          },
        );
      },
    );
  }
}

// ── Pending card ──────────────────────────────────────────────────────────────

class _PendingCard extends ConsumerWidget {
  final Transfer transfer;
  const _PendingCard({required this.transfer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => context.go('/home/transfer/${transfer.id}'),
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
            // ── Header ──────────────────────────────────────────────
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

            // ── From / file info ────────────────────────────────────
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

            // ── Accept / Decline buttons ────────────────────────────
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _handleDecline(context, ref),
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
                    onTap: () => _handleAccept(context, ref),
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

  Future<void> _handleAccept(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _AcceptDialog(transfer: transfer),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(transferServiceProvider)
          .acceptTransfer(transfer.id);
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
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeclineDialog(transfer: transfer),
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
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
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
              border:
                  Border.all(color: AppTheme.border, width: 0.5),
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
                  ...transfer.files.map(
                    (f) => Padding(
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
                    ),
                  ),
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
                  color: Colors.white,
                  fontWeight: FontWeight.w700)),
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
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
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
        style: const TextStyle(
            color: AppTheme.textSecondary, fontSize: 13),
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
                  color: Colors.white,
                  fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

// ── Dialog row helper ─────────────────────────────────────────────────────────

class _DialogRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DialogRow(
      {required this.icon,
      required this.label,
      required this.value});

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

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool incoming;
  const _EmptyState({required this.incoming});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.surfaceElevated,
                shape: BoxShape.circle,
                border:
                    Border.all(color: AppTheme.border, width: 0.5),
              ),
              child: Icon(
                incoming
                    ? Icons.move_to_inbox_rounded
                    : Icons.outbox_rounded,
                color: AppTheme.textMuted,
                size: 30,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              incoming ? 'No incoming files' : 'No sent files',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              incoming
                  ? 'Share your code with someone\nto start receiving files'
                  : 'Tap Send below to transfer files',
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 13,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 100.ms).scale(
          begin: const Offset(0.95, 0.95),
          end: const Offset(1, 1),
          curve: Curves.easeOut,
        );
  }
}

// ── Send FAB ──────────────────────────────────────────────────────────────────

class _SendFAB extends StatelessWidget {
  const _SendFAB();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton.icon(
          onPressed: () {
            HapticFeedback.mediumImpact();
            context.go('/home/send');
          },
          icon: const Icon(Icons.upload_rounded, size: 19),
          label: const Text('Send Files'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.3, end: 0);
  }
}