// lib/features/identity/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/identity_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../shared/theme/app_theme.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  String _status = 'Initializing...';
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      setState(() => _status = 'Setting up notifications...');
      await ref.read(notificationServiceProvider).init();

      setState(() => _status = 'Provisioning identity...');
      await ref.read(currentUserProvider.future);

      setState(() => _status = 'Ready');
      await Future.delayed(const Duration(milliseconds: 600));

      if (mounted) context.go('/home');
    } catch (e) {
      setState(() {
        _error = true;
        _status = 'Setup failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.primary, width: 1.5),
                ),
                child: const Icon(
                  Icons.sync_alt_rounded,
                  color: AppTheme.primary,
                  size: 40,
                ),
              )
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .scaleXY(begin: 0.8, curve: Curves.easeOutBack),

              const SizedBox(height: 32),

              Text(
                'NeoSapien',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
              )
                  .animate(delay: 200.ms)
                  .fadeIn()
                  .slideY(begin: 0.2, end: 0),

              const SizedBox(height: 8),

              Text(
                'TRANSFER',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppTheme.primary,
                      letterSpacing: 6,
                    ),
              )
                  .animate(delay: 300.ms)
                  .fadeIn(),

              const SizedBox(height: 64),

              if (!_error)
                Column(
                  children: [
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primary.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _status,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.error, size: 32),
                    const SizedBox(height: 12),
                    Text(
                      _status,
                      style: const TextStyle(color: AppTheme.error, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _error = false;
                          _status = 'Retrying...';
                        });
                        _bootstrap();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}