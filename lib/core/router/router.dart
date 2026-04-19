// lib/core/router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/identity/screens/splash_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/send/screens/send_screen.dart';
import '../../features/receive/screens/receive_screen.dart';
import '../../features/receive/screens/transfer_detail_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomeScreen(),
      routes: [
        GoRoute(
          path: 'send',
          builder: (context, state) => const SendScreen(),
        ),
        GoRoute(
          path: 'receive',
          builder: (context, state) => const ReceiveScreen(),
        ),
        GoRoute(
          path: 'transfer/:id',
          builder: (context, state) => TransferDetailScreen(
            transferId: state.pathParameters['id']!,
          ),
        ),
      ],
    ),
  ],
);