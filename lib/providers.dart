import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:neosapian_file_sharing_app/core/models/app_user.dart';
import 'package:neosapian_file_sharing_app/core/models/transfer.dart';
import 'package:neosapian_file_sharing_app/core/services/connectivity_service.dart';
import 'package:neosapian_file_sharing_app/core/services/identity_service.dart';
import 'package:neosapian_file_sharing_app/core/services/notification_service.dart';
import 'package:neosapian_file_sharing_app/core/services/transfer_service.dart';

// ─── Firebase singletons ───────────────────────────────────────────────────

final firebaseAuthProvider =
    Provider<FirebaseAuth>((_) => FirebaseAuth.instance);
final firestoreProvider =
    Provider<FirebaseFirestore>((_) => FirebaseFirestore.instance);
final messagingProvider =
    Provider<FirebaseMessaging>((_) => FirebaseMessaging.instance);

// ─── Supabase singleton ───────────────────────────────────────────────────

final supabaseClientProvider =
    Provider<SupabaseClient>((_) => Supabase.instance.client);

// ─── Core services ────────────────────────────────────────────────────────

final identityServiceProvider = Provider<IdentityService>((ref) {
  return IdentityService(
    auth: ref.read(firebaseAuthProvider),
    db: ref.read(firestoreProvider),
    fcm: ref.read(messagingProvider),
  );
});

final transferServiceProvider = Provider<TransferService>((ref) {
  return TransferService(
    db: ref.read(firestoreProvider),
    supabase: ref.read(supabaseClientProvider),
    connectivity: ref.read(connectivityServiceProvider),
  );
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(
    fcm: ref.read(messagingProvider),
    localNotifications: FlutterLocalNotificationsPlugin(),
  );
});

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final svc = ConnectivityService(connectivity: Connectivity());
  ref.onDispose(svc.dispose);
  return svc;
});

// ─── Current user state ───────────────────────────────────────────────────

final currentUserProvider = FutureProvider<AppUser>((ref) async {
  final identity = ref.read(identityServiceProvider);
  return await identity.provisionIdentity();
});

final currentUserSyncProvider = Provider<AppUser?>((ref) {
  return ref.watch(currentUserProvider).value;
});

// ─── Transfer state ───────────────────────────────────────────────────────

final incomingTransfersProvider =
    StreamProvider.autoDispose<List<Transfer>>((ref) {
  final user = ref.watch(currentUserSyncProvider);
  if (user == null) return const Stream.empty();
  return ref.read(transferServiceProvider).incomingTransfers(user.uid);
});

final outgoingTransfersProvider =
    StreamProvider.autoDispose<List<Transfer>>((ref) {
  final user = ref.watch(currentUserSyncProvider);
  if (user == null) return const Stream.empty();
  return ref.read(transferServiceProvider).outgoingTransfers(user.uid);
});

final incomingBadgeCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(incomingTransfersProvider).maybeWhen(
        data: (list) => list
            .where((t) =>
                t.status == TransferStatus.uploading ||
                t.status == TransferStatus.downloading)
            .length,
        orElse: () => 0,
      );
});

// ─── Active upload tracking ───────────────────────────────────────────────

class UploadProgressNotifier
    extends StateNotifier<Map<String, Map<String, double>>> {
  UploadProgressNotifier() : super({});

  void updateFileProgress(String transferId, String fileId, double progress) {
    final current = Map<String, Map<String, double>>.from(state);
    current[transferId] = {
      ...(current[transferId] ?? {}),
      fileId: progress,
    };
    state = current;
  }

  void clearTransfer(String transferId) {
    final current = Map<String, Map<String, double>>.from(state);
    current.remove(transferId);
    state = current;
  }

  double aggregateProgress(String transferId) {
    final files = state[transferId];
    if (files == null || files.isEmpty) return 0.0;
    return files.values.fold(0.0, (a, b) => a + b) / files.length;
  }
}

final uploadProgressProvider = StateNotifierProvider<UploadProgressNotifier,
    Map<String, Map<String, double>>>(
  (_) => UploadProgressNotifier(),
);

// ─── Recipient lookup state ───────────────────────────────────────────────

enum RecipientLookupStatus { idle, loading, found, notFound, error }

class RecipientLookupState {
  final RecipientLookupStatus status;
  final AppUser? recipient;
  final String? errorMessage;

  const RecipientLookupState({
    this.status = RecipientLookupStatus.idle,
    this.recipient,
    this.errorMessage,
  });

  RecipientLookupState copyWith({
    RecipientLookupStatus? status,
    AppUser? recipient,
    String? errorMessage,
  }) {
    return RecipientLookupState(
      status: status ?? this.status,
      recipient: recipient ?? this.recipient,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class RecipientLookupNotifier extends StateNotifier<RecipientLookupState> {
  final IdentityService _identity;

  RecipientLookupNotifier(this._identity) : super(const RecipientLookupState());

  Future<void> lookup(String code) async {
    if (code.trim().isEmpty) {
      state = const RecipientLookupState();
      return;
    }
    state = const RecipientLookupState(status: RecipientLookupStatus.loading);
    try {
      final user = await _identity.lookupByCode(code.trim().toUpperCase());
      if (user == null) {
        state = const RecipientLookupState(
          status: RecipientLookupStatus.notFound,
          errorMessage: 'No user found with that code. Check for typos.',
        );
      } else {
        state = RecipientLookupState(
          status: RecipientLookupStatus.found,
          recipient: user,
        );
      }
    } catch (e) {
      state = const RecipientLookupState(
        status: RecipientLookupStatus.error,
        errorMessage: 'Lookup failed. Check your connection.',
      );
    }
  }

  void reset() => state = const RecipientLookupState();
}

final recipientLookupProvider = StateNotifierProvider.autoDispose<
    RecipientLookupNotifier, RecipientLookupState>(
  (ref) => RecipientLookupNotifier(ref.read(identityServiceProvider)),
);

// ─── Selected files for send ──────────────────────────────────────────────

class SelectedFilesNotifier extends StateNotifier<List<File>> {
  SelectedFilesNotifier() : super([]);

  static const int maxFileSizeBytes = 500 * 1024 * 1024;

  String? validate(File file) {
    final size = file.lengthSync();
    if (size > maxFileSizeBytes) {
      final mb = (size / (1024 * 1024)).toStringAsFixed(0);
      return 'File is ${mb}MB — exceeds the 500MB limit.';
    }
    return null;
  }

  void add(File file) {
    if (!state.any((f) => f.path == file.path)) {
      state = [...state, file];
    }
  }

  void remove(File file) {
    state = state.where((f) => f.path != file.path).toList();
  }

  void clear() => state = [];
}

final selectedFilesProvider =
    StateNotifierProvider.autoDispose<SelectedFilesNotifier, List<File>>(
  (_) => SelectedFilesNotifier(),
);

// ─── Network connectivity ─────────────────────────────────────────────────

final isOnlineProvider = StreamProvider.autoDispose<bool>((ref) {
  return ref.read(connectivityServiceProvider).onlineStream;
});
