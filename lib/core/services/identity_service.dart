// lib/core/services/identity_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_user.dart';
import '../utils/short_code.dart';

const _kShortCodePref = 'user_short_code';
const _kUidPref = 'user_uid';
const int _maxCollisionRetries = 10;

class IdentityService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FirebaseMessaging _fcm;

  /// ✅ Updated to named parameters
  IdentityService({
    required FirebaseAuth auth,
    required FirebaseFirestore db,
    required FirebaseMessaging fcm,
  })  : _auth = auth,
        _db = db,
        _fcm = fcm;

  /// Sign in anonymously and provision identity
  Future<AppUser> provisionIdentity() async {
    final prefs = await SharedPreferences.getInstance();

    final savedUid = prefs.getString(_kUidPref);
    final savedCode = prefs.getString(_kShortCodePref);

    // Always ensure user is signed in
    final cred = await _auth.signInAnonymously();
    final uid = cred.user!.uid;

    // 🔍 Check Firestore first
    final userDoc = await _db.collection('users').doc(uid).get();

    if (userDoc.exists) {
      final user = AppUser.fromFirestore(userDoc);

      await prefs.setString(_kUidPref, uid);
      await prefs.setString(_kShortCodePref, user.shortCode);

      await _refreshFcmToken(user);
      return user;
    }

    // 🆕 New user
    final code = await _registerNewCode(uid);

    final user = AppUser(
      uid: uid,
      shortCode: code,
      createdAt: DateTime.now(),
    );

    await _db.collection('users').doc(uid).set(user.toFirestore());

    await prefs.setString(_kUidPref, uid);
    await prefs.setString(_kShortCodePref, code);

    await _refreshFcmToken(user);

    return user;
  }

  /// Generate unique short code with retry
  Future<String> _registerNewCode(String uid) async {
    for (var i = 0; i < _maxCollisionRetries; i++) {
      final code = ShortCodeGenerator.generate();
      final codeDoc = _db.collection('short_codes').doc(code);

      try {
        await _db.runTransaction((tx) async {
          final snap = await tx.get(codeDoc);

          if (snap.exists) {
            throw FirebaseException(
              plugin: 'cloud_firestore',
              code: 'already-exists',
            );
          }

          tx.set(codeDoc, {
            'uid': uid,
            'createdAt': FieldValue.serverTimestamp(),
          });
        });

        return code;
      } on FirebaseException catch (e) {
        if (e.code == 'already-exists') continue;
        rethrow;
      }
    }

    throw Exception('Failed to generate unique short code');
  }

  /// Lookup user by short code
  Future<AppUser?> lookupByCode(String code) async {
    final normalized = code.toUpperCase().trim();

    if (!ShortCodeGenerator.isValid(normalized)) return null;

    final codeDoc =
        await _db.collection('short_codes').doc(normalized).get();

    if (!codeDoc.exists) return null;

    final uid = codeDoc.data()!['uid'] as String;

    final userDoc = await _db.collection('users').doc(uid).get();
    if (!userDoc.exists) return null;

    return AppUser.fromFirestore(userDoc);
  }

  /// Update FCM token
  Future<void> _refreshFcmToken(AppUser user) async {
    try {
      final token = await _fcm.getToken();

      if (token != null && token != user.fcmToken) {
        await _db
            .collection('users')
            .doc(user.uid)
            .update({'fcmToken': token});
      }
    } catch (_) {
      // Silent fail (FCM optional)
    }
  }

  /// Get current user
  Future<AppUser?> currentUser() async {
    final uid = _auth.currentUser?.uid;

    if (uid == null) return null;

    final doc = await _db.collection('users').doc(uid).get();

    if (!doc.exists) return null;

    return AppUser.fromFirestore(doc);
  }
}

// ─── Providers ─────────────────────────────────────────────

final identityServiceProvider = Provider<IdentityService>((ref) {
  return IdentityService(
    auth: FirebaseAuth.instance,
    db: FirebaseFirestore.instance,
    fcm: FirebaseMessaging.instance,
  );
});

final currentUserProvider = FutureProvider<AppUser>((ref) async {
  final service = ref.read(identityServiceProvider);
  return service.provisionIdentity();
});