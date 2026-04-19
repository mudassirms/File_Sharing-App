import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import './router.dart';

/// Provides GoRouter instance to the app
final routerProvider = Provider<GoRouter>((ref) {
  return appRouter;
});