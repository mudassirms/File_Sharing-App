// lib/core/services/connectivity_service.dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConnectivityService {
  final Connectivity _connectivity;

  /// ✅ Named constructor (consistent with other services)
  ConnectivityService({
    required Connectivity connectivity,
  }) : _connectivity = connectivity;

  /// 🌐 Real-time online status
  Stream<bool> get onlineStream =>
      _connectivity.onConnectivityChanged.map(
        (results) => results.any(
          (r) => r != ConnectivityResult.none,
        ),
      );

  /// 📡 Check current connectivity
  Future<bool> get isOnline async {
    final results = await _connectivity.checkConnectivity();

    // Handles both List and single value safely
    if (results is List<ConnectivityResult>) {
      return results.any((r) => r != ConnectivityResult.none);
    } else {
      return results != ConnectivityResult.none;
    }
  }

  /// 📶 Check if on mobile data
  Future<bool> get isOnCellular async {
    final results = await _connectivity.checkConnectivity();

    if (results is List<ConnectivityResult>) {
      return results.contains(ConnectivityResult.mobile);
    } else {
      return results == ConnectivityResult.mobile;
    }
  }

  /// 🧹 Optional dispose (future-proof)
  void dispose() {
    // No stream controller to close now,
    // but keeping this for future extensibility
  }
}

// ─── Providers ─────────────────────────────────────────────

final connectivityServiceProvider =
    Provider<ConnectivityService>((ref) {
  return ConnectivityService(
    connectivity: Connectivity(),
  );
});

final isOnlineProvider = StreamProvider<bool>((ref) {
  return ref.watch(connectivityServiceProvider).onlineStream;
});