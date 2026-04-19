// lib/core/models/app_user.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String shortCode;
  final DateTime createdAt;
  final String? fcmToken;

  const AppUser({
    required this.uid,
    required this.shortCode,
    required this.createdAt,
    this.fcmToken,
  });

  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppUser(
      uid: doc.id,
      shortCode: data['shortCode'] as String,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      fcmToken: data['fcmToken'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'shortCode': shortCode,
        'createdAt': Timestamp.fromDate(createdAt),
        'fcmToken': fcmToken,
      };

  AppUser copyWith({String? fcmToken}) => AppUser(
        uid: uid,
        shortCode: shortCode,
        createdAt: createdAt,
        fcmToken: fcmToken ?? this.fcmToken,
      );
}